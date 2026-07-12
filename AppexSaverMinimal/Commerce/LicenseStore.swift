//
//  LicenseStore.swift
//  Surrealism · Commerce
//
//  Owns unlock state. Stores the key in the Keychain, validates it against the
//  backend (activating this device, ≤3), and re-validates periodically with a
//  generous offline grace so a revoked/refunded key stops cached playback after
//  the grace window (R14) while transient network failures don't lock out a
//  legitimate offline user.
//

import Foundation

@MainActor
final class LicenseStore: ObservableObject {
    enum State: Equatable {
        case locked
        case checking
        case unlocked(tier: String, packs: [String])
        case deviceLimit          // valid key, but 3 devices already active
        case revoked              // refunded/disputed/revoked
    }

    /// Transient feedback for the entry panel — why the last unlock attempt failed.
    /// Distinct from `state` so a wrong key vs. an unreachable server read differently,
    /// and a legit offline user is never told their real key is fake.
    enum EntryError: Equatable {
        case invalidKey   // server said valid:false, or the key failed the local format check
        case network      // couldn't reach the backend to verify
    }

    /// The email magic-link sign-in flow, orthogonal to the unlock `state`
    /// (sign-in is one way to arrive at `.unlocked`; pasting a key is the other).
    enum SignInPhase: Equatable {
        case idle
        case sendingLink              // calling /v1/auth/start
        case awaitingLink(email: String)  // "check your email — open the link on this Mac"
        case exchanging               // callback arrived; calling /v1/auth/exchange
        case linkExpired              // no/expired pending record, or an expired-link exchange
        case noLicense                // authenticated, but this account has no active license
    }

    @Published private(set) var state: State = .locked
    @Published private(set) var entryError: EntryError?
    @Published private(set) var signIn: SignInPhase = .idle

    /// A Surrealism key: `SURR-XXXX-XXXX-XXXX`, groups from the key alphabet
    /// (Crockford-ish, no I/L/O/U). Broad enough to never reject a real key;
    /// tight enough to catch obvious typos before a network round-trip.
    private static let keyFormat = try! NSRegularExpression(
        pattern: "^SURR-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$")

    static func looksLikeKey(_ key: String) -> Bool {
        let range = NSRange(key.startIndex..., in: key)
        return keyFormat.firstMatch(in: key, range: range) != nil
    }

    private let validator: LicenseValidating
    private let keychain: LicenseKeyStoring
    private let auth: AccountAuthenticating
    private let pendingStore: PendingAuthStoring
    private let defaults: UserDefaults
    private let deviceId: String
    private let graceInterval: TimeInterval
    /// How long a pending magic-link sign-in stays valid (matches the link's own window).
    private let pendingTTL: TimeInterval = 20 * 60

    private let kTier = "app.surrealism.tier"
    private let kPacks = "app.surrealism.packs"
    private let kLastValidated = "app.surrealism.lastValidated"
    private let kEmail = "app.surrealism.signedInEmail"

    init(validator: LicenseValidating = LiveLicenseValidator(),
         keychain: LicenseKeyStoring = KeychainLicenseStore(),
         auth: AccountAuthenticating = LiveAccountAuth(),
         pendingStore: PendingAuthStoring = KeychainPendingAuthStore(),
         defaults: UserDefaults = .standard,
         deviceId: String = DeviceID.current,
         graceDays: Double = 14) {
        self.validator = validator
        self.keychain = keychain
        self.auth = auth
        self.pendingStore = pendingStore
        self.defaults = defaults
        self.deviceId = deviceId
        self.graceInterval = graceDays * 86_400
    }

    /// The signed-in account email, for the unlocked panel's "Signed in as …" line.
    var signedInEmail: String? { defaults.string(forKey: kEmail) }

    /// Dismiss the entry error (e.g. the user started correcting the key).
    func clearEntryError() { entryError = nil }

    var isUnlocked: Bool { if case .unlocked = state { return true } else { return false } }
    var hasStoredKey: Bool { keychain.load() != nil }

    /// Enter a newly-typed key: validate + activate this device, then store on success.
    func enter(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        entryError = nil
        // Catch obvious typos instantly — no server round-trip for garbage input.
        guard Self.looksLikeKey(trimmed) else { entryError = .invalidKey; return }
        state = .checking
        do {
            let resp = try await validator.validate(key: trimmed, deviceId: deviceId)
            guard resp.valid else { entryError = .invalidKey; state = .locked; return }
            try? keychain.save(trimmed)             // valid key — keep it even at the device limit
            if resp.activation == "device_limit" {
                state = .deviceLimit
            } else {
                apply(resp)
            }
        } catch {
            // Can't confirm the key (offline, rate-limited, or 5xx). Don't call it
            // fake — say the server was unreachable so a legit user can retry.
            entryError = .network
            state = .locked
        }
    }

    // MARK: - Email sign-in (magic link + PKCE)

    /// Dismiss the sign-in flow feedback (e.g. the user starts over).
    func clearSignIn() { signIn = .idle }

    /// Begin email sign-in: generate PKCE, persist the pending record (so a link
    /// clicked after a quit still works), and ask the backend to email the link.
    func signIn(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else { entryError = .invalidKey; return }
        entryError = nil
        let pkce = PKCE()
        do {
            try pendingStore.save(PendingAuth(email: trimmed, verifier: pkce.verifier, state: pkce.state, createdAt: Date()))
            signIn = .sendingLink
            try await auth.startLogin(email: trimmed, challenge: pkce.challenge, state: pkce.state)
            signIn = .awaitingLink(email: trimmed)
        } catch {
            try? pendingStore.clear()
            signIn = .idle
            entryError = .network
        }
    }

    /// Handle a surrealism:// deep link. Validates it against the pending sign-in
    /// and, on a good callback, exchanges the code for the key.
    func handleAuthCallback(_ url: URL) async {
        // Expire a pending record older than the link window before matching.
        let pending = pendingStore.load().flatMap {
            Date().timeIntervalSince($0.createdAt) <= pendingTTL ? $0 : nil
        }
        switch AuthCallback.parse(url, expectedState: pending?.state) {
        case .notAnAuthCallback, .malformed:
            return                          // not ours / unusable → ignore
        case .stateMismatch:
            return                          // possible interception → ignore silently
        case .noPendingSignIn:
            signIn = .linkExpired           // link clicked too late, or nothing pending here
        case .code(let code):
            guard let pending else { signIn = .linkExpired; return }
            await exchange(code: code, pending: pending)
        }
    }

    private func exchange(code: String, pending: PendingAuth) async {
        signIn = .exchanging
        do {
            let key = try await auth.exchange(code: code, verifier: pending.verifier, state: pending.state)
            try? pendingStore.clear()
            defaults.set(pending.email, forKey: kEmail)
            // Feed the fetched key through the existing validate/activate/save path,
            // so device_limit, offline grace, and revocation all behave as today.
            await enter(key: key)
            signIn = .idle
        } catch AuthError.invalidGrant {
            try? pendingStore.clear()
            signIn = .linkExpired
        } catch AuthError.noLicense {
            try? pendingStore.clear()
            signIn = .noLicense
        } catch {
            // Transient/unreachable — the code is single-use server-side, so don't
            // keep the pending record; let the user request a fresh link.
            try? pendingStore.clear()
            signIn = .idle
            entryError = .network
        }
    }

    /// Call on launch and periodically. Re-validates the stored key, honoring the
    /// offline grace window when the network is unreachable.
    func revalidateIfNeeded() async {
        guard let key = keychain.load() else { state = .locked; return }
        do {
            let resp = try await validator.validate(key: key, deviceId: deviceId)
            if resp.valid && resp.activation == "device_limit" {
                state = .deviceLimit
            } else if resp.valid {
                apply(resp)
            } else {
                // Definitively revoked/refunded → clear and lock immediately.
                try? keychain.clear()
                clearCache()
                state = .revoked
            }
        } catch {
            // Network failure → fall back to the offline grace window.
            state = offlineGraceState()
        }
    }

    /// Remove the key (e.g. user signs out or a revoked key needs re-entry).
    func signOut() {
        try? keychain.clear()
        try? pendingStore.clear()
        clearCache()
        defaults.removeObject(forKey: kEmail)
        entryError = nil
        signIn = .idle
        state = .locked
    }

    // MARK: - Private

    private func apply(_ resp: ValidateResponse) {
        let tier = resp.tier ?? "unknown"
        let packs = resp.packs ?? []
        defaults.set(tier, forKey: kTier)
        defaults.set(packs, forKey: kPacks)
        defaults.set(Date().timeIntervalSince1970, forKey: kLastValidated)
        entryError = nil
        state = .unlocked(tier: tier, packs: packs)
    }

    private func offlineGraceState() -> State {
        let last = defaults.double(forKey: kLastValidated)
        guard last > 0, let tier = defaults.string(forKey: kTier) else { return .locked }
        let elapsed = Date().timeIntervalSince1970 - last
        guard elapsed <= graceInterval else { return .locked }   // grace lapsed with no successful check
        return .unlocked(tier: tier, packs: defaults.stringArray(forKey: kPacks) ?? [])
    }

    private func clearCache() {
        defaults.removeObject(forKey: kTier)
        defaults.removeObject(forKey: kPacks)
        defaults.removeObject(forKey: kLastValidated)
    }
}
