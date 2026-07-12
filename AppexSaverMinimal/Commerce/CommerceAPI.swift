//
//  CommerceAPI.swift
//  Surrealism · Commerce
//
//  Talks to the licensing/delivery backend (Cloudflare Pages). U9 uses the
//  validation endpoint; U10/U11 add catalog + download. Networking sits behind
//  a protocol so the store is testable with a fake.
//

import Foundation

enum CommerceAPI {
    /// Backend base URL. Production is surrealism.app; switch to the pages.dev
    /// URL if testing before DNS fully propagates.
    static let baseURL = URL(string: "https://surrealism.app")!
}

// MARK: - Wire models

/// Response from POST /v1/license/validate.
struct ValidateResponse: Decodable {
    let valid: Bool
    let activation: String?        // "ok" | "device_limit"
    let tier: String?
    let status: String?
    let packs: [String]?
    let message: String?
}

// MARK: - Validation service

protocol LicenseValidating {
    func validate(key: String, deviceId: String) async throws -> ValidateResponse
}

enum CommerceError: Error {
    case http(Int)
    case malformed
}

struct LiveLicenseValidator: LicenseValidating {
    var session: URLSession = .shared
    var baseURL: URL = CommerceAPI.baseURL

    func validate(key: String, deviceId: String) async throws -> ValidateResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/license/validate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["key": key, "deviceId": deviceId])
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommerceError.malformed }
        // 429 (rate limited) and 5xx are transient; surface as http errors the store can treat as "network failure".
        guard (200...299).contains(http.statusCode) else { throw CommerceError.http(http.statusCode) }
        do {
            return try JSONDecoder().decode(ValidateResponse.self, from: data)
        } catch {
            throw CommerceError.malformed
        }
    }
}

// MARK: - Account auth (app-side magic-link login)

/// Response from POST /v1/auth/exchange — the account's license key, TLS body only.
struct ExchangeResponse: Decodable { let key: String }

enum AuthError: Error {
    case invalidGrant     // expired/used link, or PKCE/state mismatch (HTTP 400)
    case noLicense        // authenticated, but the account has no active license (HTTP 404)
    case network(Int)     // transient/unreachable (429/5xx) — retryable, not a bad link
    case malformed
}

protocol AccountAuthenticating {
    /// Begin app login: send the email + PKCE challenge; the backend emails the link.
    func startLogin(email: String, challenge: String, state: String) async throws
    /// Exchange the one-time callback code (+ verifier) for the license key.
    func exchange(code: String, verifier: String, state: String) async throws -> String
}

struct LiveAccountAuth: AccountAuthenticating {
    var session: URLSession = .shared
    var baseURL: URL = CommerceAPI.baseURL

    func startLogin(email: String, challenge: String, state: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/start"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
            "state": state,
        ])
        request.timeoutInterval = 20
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.malformed }
        guard (200...299).contains(http.statusCode) else { throw AuthError.network(http.statusCode) }
    }

    func exchange(code: String, verifier: String, state: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/exchange"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Secrets (code, verifier, and the returned key) travel in the body, never the URL.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code, "code_verifier": verifier, "state": state,
        ])
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.malformed }
        switch http.statusCode {
        case 200...299:
            do { return try JSONDecoder().decode(ExchangeResponse.self, from: data).key }
            catch { throw AuthError.malformed }
        case 400: throw AuthError.invalidGrant   // invalid_grant / invalid_request → treat as a bad/expired link
        case 404: throw AuthError.noLicense
        default: throw AuthError.network(http.statusCode)  // 429/5xx are transient
        }
    }
}

// MARK: - Catalog (U10)

/// One loop as returned by GET /v1/catalog. `entitled` reflects the caller's tier.
struct CatalogLoop: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let poster: String?
    let size: Int?
    let checksum: String?
    let tierTag: String
    let isSample: Bool
    let entitled: Bool
}
private struct CatalogResponse: Decodable { let loops: [CatalogLoop] }

protocol CatalogFetching {
    func catalog(key: String?) async throws -> [CatalogLoop]
}

struct LiveCatalogFetcher: CatalogFetching {
    var session: URLSession = .shared
    var baseURL: URL = CommerceAPI.baseURL

    func catalog(key: String?) async throws -> [CatalogLoop] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/catalog"))
        if let key, !key.isEmpty { request.setValue(key, forHTTPHeaderField: "x-license-key") } // never in the URL
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CommerceError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try JSONDecoder().decode(CatalogResponse.self, from: data).loops
    }
}

// MARK: - Download authorization (U11)

/// Response from POST /v1/download — a short-lived presigned R2 URL.
struct DownloadGrant: Decodable {
    let url: String
    let expiresIn: Int?
    let checksum: String?
    let size: Int?
}

protocol DownloadAuthorizing {
    /// key/deviceId are optional — free sample loops need no license.
    func authorize(key: String?, deviceId: String?, loopId: String) async throws -> DownloadGrant
}

enum DownloadError: Error { case denied(Int), checksumMismatch, urlExpired }

struct LiveDownloadAuthorizer: DownloadAuthorizing {
    var session: URLSession = .shared
    var baseURL: URL = CommerceAPI.baseURL

    func authorize(key: String?, deviceId: String?, loopId: String) async throws -> DownloadGrant {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/download"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: String] = ["loopId": loopId]
        if let key { payload["key"] = key }
        if let deviceId { payload["deviceId"] = deviceId }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommerceError.malformed }
        guard (200...299).contains(http.statusCode) else { throw DownloadError.denied(http.statusCode) }
        return try JSONDecoder().decode(DownloadGrant.self, from: data)
    }
}
