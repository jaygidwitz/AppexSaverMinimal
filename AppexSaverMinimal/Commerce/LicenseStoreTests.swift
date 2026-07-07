//
//  LicenseStoreTests.swift
//  Surrealism · Commerce
//
//  Unit tests for the unlock flow's failure feedback: a fake key must surface
//  `.invalidKey`, an unreachable server `.network` — never conflated with a
//  revoked/valid state.
//
//  NOTE: not yet wired into a test target. To run these:
//    1. In Xcode: File ▸ New ▸ Target… ▸ Unit Testing Bundle
//       (name e.g. "AppexSaverMinimalTests", host app = AppexSaverMinimal).
//    2. Add this file to that target (File Inspector ▸ Target Membership).
//    3. ⌘U.
//  Left in the Commerce group so it's easy to find; move into the test target's
//  group once created.
//

import XCTest
@testable import AppexSaverMinimal

private final class FakeValidator: LicenseValidating {
    var result: Result<ValidateResponse, Error>
    private(set) var callCount = 0
    init(_ result: Result<ValidateResponse, Error>) { self.result = result }
    func validate(key: String, deviceId: String) async throws -> ValidateResponse {
        callCount += 1
        return try result.get()
    }
}

private final class FakeKeychain: LicenseKeyStoring {
    var stored: String?
    func save(_ key: String) throws { stored = key }
    func load() -> String? { stored }
    func clear() throws { stored = nil }
}

private func makeResponse(valid: Bool, activation: String? = nil, tier: String? = nil) -> ValidateResponse {
    ValidateResponse(valid: valid, activation: activation, tier: tier, status: valid ? "active" : nil, packs: nil, message: nil)
}

@MainActor
final class LicenseStoreTests: XCTestCase {

    private func makeStore(validator: LicenseValidating, keychain: FakeKeychain = FakeKeychain()) -> LicenseStore {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return LicenseStore(validator: validator, keychain: keychain, defaults: defaults, deviceId: "test-device")
    }

    // A well-formed key the server rejects → invalidKey, and it never gets stored.
    func testServerRejectsKey_setsInvalidKey() async {
        let keychain = FakeKeychain()
        let store = makeStore(validator: FakeValidator(.success(makeResponse(valid: false))), keychain: keychain)

        await store.enter(key: "SURR-8F3K-QZ29-M7BX")

        XCTAssertEqual(store.entryError, .invalidKey)
        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(keychain.stored, "an invalid key must not be persisted")
    }

    // Garbage that fails the local format check → invalidKey with no network call.
    func testMalformedKey_shortCircuitsBeforeNetwork() async {
        let validator = FakeValidator(.success(makeResponse(valid: true, activation: "ok", tier: "lifetime-base")))
        let store = makeStore(validator: validator)

        await store.enter(key: "hello there")

        XCTAssertEqual(store.entryError, .invalidKey)
        XCTAssertEqual(validator.callCount, 0, "malformed input must not hit the server")
    }

    // Network/5xx/offline → network error, NOT invalidKey (a real key mustn't read as fake).
    func testNetworkFailure_setsNetworkError() async {
        let store = makeStore(validator: FakeValidator(.failure(CommerceError.http(503))))

        await store.enter(key: "SURR-8F3K-QZ29-M7BX")

        XCTAssertEqual(store.entryError, .network)
        XCTAssertEqual(store.state, .locked)
    }

    // A valid key clears any prior error and unlocks + persists.
    func testValidKey_unlocksAndClearsError() async {
        let keychain = FakeKeychain()
        let store = makeStore(validator: FakeValidator(.success(makeResponse(valid: true, activation: "ok", tier: "lifetime-base"))), keychain: keychain)

        await store.enter(key: "SURR-8F3K-QZ29-M7BX")

        XCTAssertNil(store.entryError)
        XCTAssertEqual(store.state, .unlocked(tier: "lifetime-base", packs: []))
        XCTAssertEqual(keychain.stored, "SURR-8F3K-QZ29-M7BX")
    }

    func testLooksLikeKey_acceptsRealShapeRejectsGarbage() {
        XCTAssertTrue(LicenseStore.looksLikeKey("SURR-8F3K-QZ29-M7BX"))
        XCTAssertFalse(LicenseStore.looksLikeKey("SURR-8F3K-QZ29"))       // too short
        XCTAssertFalse(LicenseStore.looksLikeKey("8F3K-QZ29-M7BX"))       // no prefix
        XCTAssertFalse(LicenseStore.looksLikeKey("hello there"))
    }
}
