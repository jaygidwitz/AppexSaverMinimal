//
//  TheaterPresentationTests.swift
//  Surrealism
//
//  Unit coverage for the Theater's pure state models (U2): fullscreen⇄windowed
//  toggle and the one-time first-run key-hint flag. The window/overlay behavior
//  itself is verified by running.
//

import XCTest
@testable import Surrealism

final class TheaterPresentationTests: XCTestCase {

    func testPresentation_toggles() {
        XCTAssertEqual(TheaterPresentation.fullscreen.toggled, .windowed)
        XCTAssertEqual(TheaterPresentation.windowed.toggled, .fullscreen)
        XCTAssertEqual(TheaterPresentation.fullscreen.toggled.toggled, .fullscreen)
    }

    func testFirstRunHint_showsOnceThenNever() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        XCTAssertTrue(TheaterHint.shouldShow(defaults), "hint shows on a fresh install")
        TheaterHint.markShown(defaults)
        XCTAssertFalse(TheaterHint.shouldShow(defaults), "never again after first open")
    }
}
