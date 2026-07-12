//
//  AuthCallbackRouterTests.swift
//  Surrealism · Commerce
//

import XCTest
@testable import Surrealism

final class AuthCallbackRouterTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testValidCallback_matchingState_returnsCode() {
        let r = AuthCallback.parse(url("surrealism://auth/callback?code=abc123&state=st"), expectedState: "st")
        XCTAssertEqual(r, .code("abc123"))
    }

    func testStateMismatch_isRejected() {
        let r = AuthCallback.parse(url("surrealism://auth/callback?code=abc123&state=evil"), expectedState: "st")
        XCTAssertEqual(r, .stateMismatch)
    }

    func testNoPendingSignIn_wellFormedCallback_mapsToNoPending() {
        // expectedState nil = no pending / expired → surface "link expired", don't drop it.
        let r = AuthCallback.parse(url("surrealism://auth/callback?code=abc123&state=st"), expectedState: nil)
        XCTAssertEqual(r, .noPendingSignIn)
    }

    func testUnrelatedURL_isIgnored() {
        XCTAssertEqual(AuthCallback.parse(url("surrealism://other/thing?x=1"), expectedState: "st"), .notAnAuthCallback)
        XCTAssertEqual(AuthCallback.parse(url("https://surrealism.app/auth/callback?code=x&state=st"), expectedState: "st"), .notAnAuthCallback)
    }

    func testMissingCode_isMalformed() {
        let r = AuthCallback.parse(url("surrealism://auth/callback?state=st"), expectedState: "st")
        XCTAssertEqual(r, .malformed)
    }
}
