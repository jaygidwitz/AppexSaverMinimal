//
//  PKCE.swift
//  Surrealism · Commerce
//
//  PKCE (RFC 7636) material for the app's magic-link sign-in. The app is a public
//  native client (RFC 8252): it generates and holds the verifier, and only the
//  S256 challenge + a state nonce ever leave the device. This is what makes the
//  non-exclusive surrealism:// callback safe — an app that squats the scheme and
//  intercepts the code still can't complete the exchange without the verifier.
//

import Foundation
import CryptoKit

struct PKCE: Equatable {
    let verifier: String   // held on-device; sent only in the code→key exchange body
    let challenge: String  // base64url(SHA256(verifier)); sent to /v1/auth/start
    let state: String      // opaque nonce echoed back on the callback

    init() {
        verifier = Self.randomURLSafe(byteCount: 32)   // 43-char base64url; within RFC 7636's 43–128
        challenge = Self.s256Challenge(verifier)
        state = Self.randomURLSafe(byteCount: 16)
    }

    /// RFC 7636 S256: base64url(SHA-256(verifier)), no padding.
    static func s256Challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// High-entropy URL-safe string from `byteCount` random bytes.
    static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
