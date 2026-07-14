//
//  WallpaperControllerTests.swift
//  Surrealism
//
//  U3 coverage for the parts that are pure/inspectable: the display-set
//  reconciliation planner and the wallpaper window's configuration (desktop level,
//  click-through, all-spaces). The behind-icons rendering + multi-monitor behavior
//  is verified by running on-device.
//

import XCTest
import AppKit
@testable import Surrealism

@MainActor
final class WallpaperControllerTests: XCTestCase {

    func testPlan_addsAndRemovesByDisplaySet() {
        // 2 displays → 1: display 2 removed.
        var r = WallpaperController.plan(current: [1], existing: [1, 2])
        XCTAssertEqual(r.add, [])
        XCTAssertEqual(r.remove, [2])

        // 1 display → 3: two added, none removed.
        r = WallpaperController.plan(current: [1, 2, 3], existing: [1])
        XCTAssertEqual(Set(r.add), Set([2, 3]))
        XCTAssertEqual(r.remove, [])

        // No change (order-insensitive).
        r = WallpaperController.plan(current: [5, 6], existing: [6, 5])
        XCTAssertEqual(r.add, [])
        XCTAssertEqual(r.remove, [])

        // Full swap.
        r = WallpaperController.plan(current: [9], existing: [1])
        XCTAssertEqual(r.add, [9])
        XCTAssertEqual(r.remove, [1])
    }

    func testWallpaperWindow_isDesktopLevelClickThroughAllSpaces() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first, "needs a screen")
        let win = WallpaperWindow(screen: screen)
        XCTAssertEqual(win.level, WallpaperWindow.desktopLevel, "renders behind the desktop icons")
        XCTAssertTrue(win.ignoresMouseEvents, "desktop clicks pass through")
        XCTAssertTrue(win.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(win.collectionBehavior.contains(.stationary))
        XCTAssertFalse(win.hasShadow)
    }
}
