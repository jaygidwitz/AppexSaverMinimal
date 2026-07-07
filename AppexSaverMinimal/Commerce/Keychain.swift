//
//  Keychain.swift
//  Surrealism · Commerce
//
//  The license key is the one secret the buyer holds — stored in the Keychain,
//  never UserDefaults. Behind a protocol so the store is testable with a fake.
//

import Foundation
import Security

protocol LicenseKeyStoring {
    func save(_ key: String) throws
    func load() -> String?
    func clear() throws
}

struct KeychainLicenseStore: LicenseKeyStoring {
    let service = "app.surrealism.license"
    let account = "licenseKey"

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func save(_ key: String) throws {
        let data = Data(key.utf8)
        // Upsert: delete any existing item, then add.
        SecItemDelete(baseQuery as CFDictionary)
        var attrs = baseQuery
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

enum KeychainError: Error { case status(OSStatus) }
