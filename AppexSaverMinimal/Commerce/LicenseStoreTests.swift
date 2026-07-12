//
//  LicenseStoreTests.swift
//  Surrealism · Commerce
//
//  Unit tests for the unlock flow's failure feedback and the email sign-in flow.
//  A fake key must surface `.invalidKey`, an unreachable server `.network` — never
//  conflated with a revoked/valid state; sign-in drives the pending/exchange states.
//
//  Runs in the AppexSaverMinimalTests target:
//    xcodebuild test -scheme AppexSaverMinimal -destination 'platform=macOS'
//

import XCTest
@testable import Surrealism

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

private final class FakeAuth: AccountAuthenticating {
    var startError: Error?
    var exchangeResult: Result<String, Error>
    private(set) var startCount = 0
    private(set) var exchangeCount = 0
    init(exchange: Result<String, Error> = .success("SURR-8F3K-QZ29-M7BX")) { exchangeResult = exchange }
    func startLogin(email: String, challenge: String, state: String) async throws {
        startCount += 1
        if let startError { throw startError }
    }
    func exchange(code: String, verifier: String, state: String) async throws -> String {
        exchangeCount += 1
        return try exchangeResult.get()
    }
}

private final class FakePendingStore: PendingAuthStoring {
    var stored: PendingAuth?
    func save(_ pending: PendingAuth) throws { stored = pending }
    func load() -> PendingAuth? { stored }
    func clear() throws { stored = nil }
}

@MainActor
final class LicenseStoreTests: XCTestCase {

    private func makeStore(validator: LicenseValidating,
                           keychain: FakeKeychain = FakeKeychain(),
                           auth: AccountAuthenticating = FakeAuth(),
                           pendingStore: PendingAuthStoring = FakePendingStore()) -> LicenseStore {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return LicenseStore(validator: validator, keychain: keychain, auth: auth,
                            pendingStore: pendingStore, defaults: defaults, deviceId: "test-device")
    }

    private func validResponseValidator() -> FakeValidator {
        FakeValidator(.success(makeResponse(valid: true, activation: "ok", tier: "lifetime-base")))
    }

    private func urlFor(state: String, code: String = "code-123") -> URL {
        URL(string: "surrealism://auth/callback?code=\(code)&state=\(state)")!
    }

    // MARK: - Email sign-in

    // signIn persists a pending record and, on a successful start, awaits the link.
    func testSignIn_persistsPending_andAwaitsLink() async {
        let pending = FakePendingStore()
        let store = makeStore(validator: validResponseValidator(), auth: FakeAuth(), pendingStore: pending)

        await store.signIn(email: "buyer@example.com")

        XCTAssertEqual(store.signIn, .awaitingLink(email: "buyer@example.com"))
        XCTAssertNotNil(pending.stored, "the verifier must be persisted so a post-quit link still works")
        XCTAssertEqual(pending.stored?.email, "buyer@example.com")
    }

    // Full happy path: sign in → callback with the matching state → exchange → unlock + email shown.
    func testCallback_exchangeSuccess_unlocksAndStoresEmail() async {
        let keychain = FakeKeychain()
        let pending = FakePendingStore()
        let store = makeStore(validator: validResponseValidator(), keychain: keychain,
                              auth: FakeAuth(exchange: .success("SURR-8F3K-QZ29-M7BX")), pendingStore: pending)
        await store.signIn(email: "buyer@example.com")
        let state = pending.stored!.state

        await store.handleAuthCallback(urlFor(state: state))

        XCTAssertEqual(store.state, .unlocked(tier: "lifetime-base", packs: []))
        XCTAssertEqual(store.signedInEmail, "buyer@example.com")
        XCTAssertEqual(keychain.stored, "SURR-8F3K-QZ29-M7BX")
        XCTAssertNil(pending.stored, "pending record is cleared on success")
        XCTAssertEqual(store.signIn, .idle)
    }

    // Exchange returns no_license → a distinct, non-error state (not invalidKey/network).
    func testCallback_noLicense_setsNoLicense() async {
        let pending = FakePendingStore()
        let store = makeStore(validator: validResponseValidator(),
                              auth: FakeAuth(exchange: .failure(AuthError.noLicense)), pendingStore: pending)
        await store.signIn(email: "buyer@example.com")

        await store.handleAuthCallback(urlFor(state: pending.stored!.state))

        XCTAssertEqual(store.signIn, .noLicense)
        XCTAssertEqual(store.state, .locked)
    }

    // Expired/used link (invalid_grant) → linkExpired, not invalidKey.
    func testCallback_invalidGrant_setsLinkExpired() async {
        let pending = FakePendingStore()
        let store = makeStore(validator: validResponseValidator(),
                              auth: FakeAuth(exchange: .failure(AuthError.invalidGrant)), pendingStore: pending)
        await store.signIn(email: "buyer@example.com")

        await store.handleAuthCallback(urlFor(state: pending.stored!.state))

        XCTAssertEqual(store.signIn, .linkExpired)
    }

    // A callback whose state doesn't match the pending sign-in is ignored (no exchange).
    func testCallback_stateMismatch_isIgnored() async {
        let pending = FakePendingStore()
        let auth = FakeAuth()
        let store = makeStore(validator: validResponseValidator(), auth: auth, pendingStore: pending)
        await store.signIn(email: "buyer@example.com")

        await store.handleAuthCallback(urlFor(state: "not-the-pending-state"))

        XCTAssertEqual(auth.exchangeCount, 0, "a mismatched state must not trigger an exchange")
        XCTAssertEqual(store.signIn, .awaitingLink(email: "buyer@example.com"))
    }

    // An expired pending record → the callback surfaces linkExpired (post-quit, clicked too late).
    func testCallback_expiredPending_setsLinkExpired() async {
        let pending = FakePendingStore()
        let store = makeStore(validator: validResponseValidator(), pendingStore: pending)
        await store.signIn(email: "buyer@example.com")
        let state = pending.stored!.state
        // Age the pending record beyond the link window.
        let old = pending.stored!
        pending.stored = PendingAuth(email: old.email, verifier: old.verifier, state: old.state,
                                     createdAt: Date(timeIntervalSinceNow: -3600))

        await store.handleAuthCallback(urlFor(state: state))

        XCTAssertEqual(store.signIn, .linkExpired)
    }

    // Sign-out clears the signed-in email and any pending record.
    func testSignOut_clearsEmailAndPending() async {
        let keychain = FakeKeychain()
        let pending = FakePendingStore()
        let store = makeStore(validator: validResponseValidator(), keychain: keychain,
                              auth: FakeAuth(exchange: .success("SURR-8F3K-QZ29-M7BX")), pendingStore: pending)
        await store.signIn(email: "buyer@example.com")
        await store.handleAuthCallback(urlFor(state: pending.stored?.state ?? ""))
        XCTAssertEqual(store.signedInEmail, "buyer@example.com")

        store.signOut()

        XCTAssertNil(store.signedInEmail)
        XCTAssertNil(pending.stored)
        XCTAssertEqual(store.state, .locked)
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
