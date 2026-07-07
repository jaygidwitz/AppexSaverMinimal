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
