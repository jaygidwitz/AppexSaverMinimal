//
//  CatalogModel.swift
//  Surrealism · Commerce
//
//  Loads the loop catalog from the backend, marking each loop entitled/locked
//  for the current license (key read from the Keychain, sent as a header).
//

import Foundation

@MainActor
final class CatalogModel: ObservableObject {
    @Published private(set) var loops: [CatalogLoop] = []
    @Published private(set) var loading = false
    @Published private(set) var loadError: String?

    private let fetcher: CatalogFetching
    private let keychain: LicenseKeyStoring

    init(fetcher: CatalogFetching = LiveCatalogFetcher(),
         keychain: LicenseKeyStoring = KeychainLicenseStore()) {
        self.fetcher = fetcher
        self.keychain = keychain
    }

    func load() async {
        loading = true
        loadError = nil
        do {
            loops = try await fetcher.catalog(key: keychain.load())
        } catch {
            loadError = "Couldn't load the catalog. Check your connection."
        }
        loading = false
    }
}
