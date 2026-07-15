//
//  Telemetry.swift
//  Surrealism
//
//  Anonymous usage events → the same GA4 property as the website
//  (G-58PPSFN96T), via the Measurement Protocol — no SDK. App events are
//  prefixed app_* and stamped platform:"macos" so web reporting stays
//  filterable (one property, one funnel: web purchase → app activation).
//
//  Privacy: a persisted random UUID is the only identifier; never send license
//  keys, emails, or file paths. The "Share anonymous usage data" toggle
//  (PlaybackControlsView) turns it off entirely. Host-app only.
//

import Foundation

@MainActor
final class Telemetry: ObservableObject {

    nonisolated static let measurementID = "G-58PPSFN96T"
    /// Paste a Measurement Protocol API secret (GA4 Admin → Data streams →
    /// MP API secrets — create one for the app, separate from the webhook's so
    /// either can be rotated alone). Until then telemetry is a silent no-op.
    /// An MP secret in a shipped binary is expected and write-only.
    nonisolated static let placeholderSecret = "REPLACE_WITH_MP_API_SECRET"
    nonisolated static let apiSecret = "KODh36O_QE2l-jwEGEHTCg"

    /// Process-wide instance used by call sites; tests build their own.
    static let shared = Telemetry()

    @Published private(set) var enabled: Bool

    private let defaults: UserDefaults
    private let apiSecret: String
    private let transport: (URL, Data) -> Void
    private let kEnabled = "app.surrealism.telemetry.enabled"
    private let kClientId = "app.surrealism.telemetry.clientId"

    /// Default transport: fire-and-forget URLSession POST. Failures are
    /// ignored — telemetry must never surface as app behavior.
    nonisolated private static func post(_ url: URL, _ body: Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }

    init(defaults: UserDefaults = .standard,
         apiSecret: String = Telemetry.apiSecret,
         transport: @escaping (URL, Data) -> Void = Telemetry.post) {
        self.defaults = defaults
        self.apiSecret = apiSecret
        self.transport = transport
        self.enabled = defaults.object(forKey: kEnabled) as? Bool ?? true
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: kEnabled)
    }

    /// The per-install anonymous id, minted on first use.
    private var clientId: String {
        if let existing = defaults.string(forKey: kClientId) { return existing }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: kClientId)
        return fresh
    }

    /// Fire-and-forget event. No-ops when the toggle is off, no real API
    /// secret is configured, or the process is the unit-test host with the
    /// default transport (tests inject their own).
    func send(_ name: String, params: [String: Any] = [:]) {
        guard enabled, apiSecret != Telemetry.placeholderSecret else { return }
        // Production-configured instances (Telemetry.shared at call sites) stay
        // silent in the unit-test host; test instances inject their own secret.
        if ProcessInfo.processInfo.isRunningUnitTests, apiSecret == Telemetry.apiSecret { return }

        var merged = params
        merged["platform"] = "macos"
        merged["app_version"] =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        // Marks the event "engaged" so it registers in standard GA4 reports.
        merged["engagement_time_msec"] = 1

        let payload: [String: Any] = [
            "client_id": clientId,
            "non_personalized_ads": true,
            "events": [["name": name, "params": merged]],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string:
                "https://www.google-analytics.com/mp/collect?measurement_id=\(Self.measurementID)&api_secret=\(apiSecret)")
        else { return }
        transport(url, body)
    }
}
