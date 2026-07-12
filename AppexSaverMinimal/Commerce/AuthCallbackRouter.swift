//
//  AuthCallbackRouter.swift
//  Surrealism · Commerce
//
//  Parses the surrealism://auth/callback magic-link return and validates it
//  against the pending sign-in. Pure and testable — no side effects. The store
//  (LicenseStore) decides what to do with each outcome.
//

import Foundation

enum AuthCallback {
    enum Result: Equatable {
        case code(String)        // valid callback for the pending sign-in — ready to exchange
        case stateMismatch       // state doesn't match the pending sign-in — possible interception; ignore
        case noPendingSignIn     // no pending (or expired) sign-in — surface "link expired"
        case notAnAuthCallback   // unrelated surrealism:// URL — ignore silently
        case malformed           // auth callback but missing/empty code
    }

    /// `expectedState` is the pending sign-in's state, or nil when there is no
    /// pending (or it has expired) — in which case a well-formed callback maps to
    /// `.noPendingSignIn` rather than being silently dropped.
    static func parse(_ url: URL, expectedState: String?) -> Result {
        guard url.scheme == "surrealism", url.host == "auth", url.path == "/callback" else {
            return .notAnAuthCallback
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value
        let state = comps?.queryItems?.first(where: { $0.name == "state" })?.value
        guard let code, !code.isEmpty, state != nil else { return .malformed }
        guard let expectedState else { return .noPendingSignIn }
        guard state == expectedState else { return .stateMismatch }
        return .code(code)
    }
}
