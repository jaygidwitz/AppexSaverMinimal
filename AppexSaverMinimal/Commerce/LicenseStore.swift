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

    @Published private(set) var state: State = .locked

    private let validator: LicenseValidating
    private let keychain: LicenseKeyStoring
    private let defaults: UserDefaults
    private let deviceId: String
    private let graceInterval: TimeInterval

    private let kTier = "app.surrealism.tier"
    private let kPacks = "app.surrealism.packs"
    private let kLastValidated = "app.surrealism.lastValidated"

    init(validator: LicenseValidating = LiveLicenseValidator(),
         keychain: LicenseKeyStoring = KeychainLicenseStore(),
         defaults: UserDefaults = .standard,
         deviceId: String = DeviceID.current,
         graceDays: Double = 14) {
        self.validator = validator
        self.keychain = keychain
        self.defaults = defaults
        self.deviceId = deviceId
        self.graceInterval = graceDays * 86_400
    }

    var isUnlocked: Bool { if case .unlocked = state { return true } else { return false } }
    var hasStoredKey: Bool { keychain.load() != nil }

    /// Enter a newly-typed key: validate + activate this device, then store on success.
    func enter(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return }
        state = .checking
        do {
            let resp = try await validator.validate(key: trimmed, deviceId: deviceId)
            guard resp.valid else { state = .locked; return }
            try? keychain.save(trimmed)             // valid key — keep it even at the device limit
            if resp.activation == "device_limit" {
                state = .deviceLimit
            } else {
                apply(resp)
            }
        } catch {
            // Can't confirm a brand-new key offline — stay locked (nothing cached to trust).
            state = .locked
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
        clearCache()
        state = .locked
    }

    // MARK: - Private

    private func apply(_ resp: ValidateResponse) {
        let tier = resp.tier ?? "unknown"
        let packs = resp.packs ?? []
        defaults.set(tier, forKey: kTier)
        defaults.set(packs, forKey: kPacks)
        defaults.set(Date().timeIntervalSince1970, forKey: kLastValidated)
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
