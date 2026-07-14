//
//  MenuBarAgentTests.swift
//  Surrealism
//
//  U4 coverage: the last-window-close terminate decision (keeps the process alive
//  while wallpaper runs) and the status-item install/remove lifecycle. Persist-
//  after-window-close and the Open/Quit behaviors are verified by running.
//

import XCTest
@testable import Surrealism

@MainActor
final class MenuBarAgentTests: XCTestCase {

    func testTerminateHandler_keepsProcessAliveWhileWallpaperActive() {
        XCTAssertFalse(AmbientLifecycle.shouldTerminateAfterLastWindowClosed(wallpaperActive: true),
                       "must not quit on last-window-close while wallpaper is running")
        XCTAssertTrue(AmbientLifecycle.shouldTerminateAfterLastWindowClosed(wallpaperActive: false),
                      "normal quit-on-last-window-close when no wallpaper")
    }

    func testAgent_installIsIdempotentAndRemovable() {
        let agent = MenuBarAgent(onTogglePause: {}, onNext: {}, onStopWallpaper: {}, onOpen: {}, onQuit: {})

        XCTAssertFalse(agent.isInstalled)
        agent.install()
        XCTAssertTrue(agent.isInstalled)
        agent.install() // idempotent — no second status item
        XCTAssertTrue(agent.isInstalled)
        agent.remove()
        XCTAssertFalse(agent.isInstalled)
    }
}
