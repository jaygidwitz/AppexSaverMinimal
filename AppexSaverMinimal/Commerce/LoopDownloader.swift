//
//  LoopDownloader.swift
//  Surrealism · Commerce
//
//  Downloads entitled loops into the shared cache the screensaver reads
//  (/Users/Shared/AppexSaverMinimal/videos). Requests a short-lived presigned
//  R2 URL per loop, verifies the checksum before committing the file, and
//  re-authorizes + restarts once if the URL expired mid-transfer.
//

import Foundation
import CryptoKit

@MainActor
final class LoopDownloader: ObservableObject {
    @Published private(set) var downloading: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]

    private let authorizer: DownloadAuthorizing
    private let keychain: LicenseKeyStoring
    private let session: URLSession
    private let deviceId: String
    private let cacheDir: URL

    init(authorizer: DownloadAuthorizing = LiveDownloadAuthorizer(),
         keychain: LicenseKeyStoring = KeychainLicenseStore(),
         session: URLSession = .shared,
         deviceId: String = DeviceID.current,
         cacheDirectory: String = VideoCache.directory) {
        self.authorizer = authorizer
        self.keychain = keychain
        self.session = session
        self.deviceId = deviceId
        self.cacheDir = URL(fileURLWithPath: cacheDirectory, isDirectory: true)
    }

    func isDownloaded(_ loopId: String) -> Bool {
        FileManager.default.fileExists(atPath: destination(for: loopId).path)
    }

    func download(_ loop: CatalogLoop) async {
        guard let key = keychain.load() else { errors[loop.id] = "No license on this device."; return }
        downloading.insert(loop.id)
        errors[loop.id] = nil
        defer { downloading.remove(loop.id) }
        do {
            try await attempt(loop, key: key)
        } catch DownloadError.urlExpired {
            do { try await attempt(loop, key: key) }              // fresh presign + restart, once
            catch { errors[loop.id] = message(for: error) }
        } catch {
            errors[loop.id] = message(for: error)
        }
    }

    func remove(_ loopId: String) {
        try? FileManager.default.removeItem(at: destination(for: loopId))
    }

    // MARK: - Private

    private func attempt(_ loop: CatalogLoop, key: String) async throws {
        let grant = try await authorizer.authorize(key: key, deviceId: deviceId, loopId: loop.id)
        guard let url = URL(string: grant.url) else { throw CommerceError.malformed }

        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let (tempURL, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 { throw DownloadError.urlExpired }

        if let expected = grant.checksum ?? loop.checksum, expected != "PLACEHOLDER" {
            guard try sha256(of: tempURL) == expected else {
                try? FileManager.default.removeItem(at: tempURL)
                throw DownloadError.checksumMismatch
            }
        }

        let dest = destination(for: loop.id)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
    }

    private func destination(for loopId: String) -> URL {
        cacheDir.appendingPathComponent("\(loopId).mp4")
    }

    private func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func message(for error: Error) -> String {
        switch error {
        case DownloadError.checksumMismatch: return "Download was corrupted — try again."
        case DownloadError.denied(let code): return "Not authorized (\(code))."
        default: return "Download failed — try again."
        }
    }
}
