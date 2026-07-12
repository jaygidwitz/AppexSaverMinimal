//
//  PKCETests.swift
//  Surrealism · Commerce
//

import XCTest
@testable import AppexSaverMinimal

final class PKCETests: XCTestCase {

    // RFC 7636 Appendix B test vector — must match the backend's S256 computation.
    func testS256Challenge_matchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(PKCE.s256Challenge(verifier), expected)
    }

    func testInit_producesConsistentChallengeForItsVerifier() {
        let pkce = PKCE()
        XCTAssertEqual(pkce.challenge, PKCE.s256Challenge(pkce.verifier))
    }

    func testMaterial_isURLSafeAndHighEntropy() {
        let a = PKCE()
        let b = PKCE()
        // Distinct across instances (verifier + state are random).
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertNotEqual(a.state, b.state)
        // base64url only — no +, /, or = padding.
        for s in [a.verifier, a.challenge, a.state] {
            XCTAssertFalse(s.contains("+"))
            XCTAssertFalse(s.contains("/"))
            XCTAssertFalse(s.contains("="))
        }
        // RFC 7636: verifier length 43–128.
        XCTAssertGreaterThanOrEqual(a.verifier.count, 43)
    }
}
