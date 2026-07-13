//
//  PlaybackCommandsTests.swift
//  Surrealism
//
//  Unit coverage for the shared transport command set (U1): fan-out across the
//  active controller set, cross-fade clamping, shuffle persistence, and
//  active-surface gating. Runs in AppexSaverMinimalTests.
//

import XCTest
@testable import Surrealism

@MainActor
final class PlaybackCommandsTests: XCTestCase {

    private func makeSettings() -> PlaybackSettings {
        PlaybackSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    private func makeController() -> VideoPlayerController {
        VideoPlayerController(videos: [URL(fileURLWithPath: "/tmp/loop-\(UUID().uuidString).mp4")], shuffle: false)
    }

    func testPlayPause_fansOutAcrossTheWholeSet() {
        let controllers = [makeController(), makeController(), makeController()]
        let cmd = PlaybackCommands(settings: makeSettings(), controllers: { controllers })

        XCTAssertTrue(cmd.isPlaying)
        cmd.playPause() // → paused
        XCTAssertFalse(cmd.isPlaying)
        XCTAssertTrue(controllers.allSatisfy { $0.isPaused }, "pause fans out to every display's controller")

        cmd.playPause() // → playing
        XCTAssertTrue(cmd.isPlaying)
        XCTAssertTrue(controllers.allSatisfy { !$0.isPaused }, "resume fans out to every controller")
    }

    func testCrossFadeStep_clampsAtBothEnds() {
        let settings = makeSettings()
        let cmd = PlaybackCommands(settings: settings, controllers: { [] })

        settings.setCrossFadeSeconds(PlaybackSettings.fadeRange.upperBound)
        cmd.crossFadeStep(+1)
        XCTAssertEqual(settings.crossFadeSeconds, PlaybackSettings.fadeRange.upperBound, accuracy: 0.0001)

        settings.setCrossFadeSeconds(PlaybackSettings.fadeRange.lowerBound)
        cmd.crossFadeStep(-1)
        XCTAssertEqual(settings.crossFadeSeconds, PlaybackSettings.fadeRange.lowerBound, accuracy: 0.0001)
    }

    func testCrossFadeStep_movesByOneStep() {
        let settings = makeSettings()
        settings.setCrossFadeSeconds(2.0)
        let cmd = PlaybackCommands(settings: settings, controllers: { [] })
        cmd.crossFadeStep(+1)
        XCTAssertEqual(settings.crossFadeSeconds, 2.0 + PlaybackCommands.crossFadeStepSeconds, accuracy: 0.0001)
    }

    func testToggleShuffle_flipsAndPersists() {
        let settings = makeSettings()
        let start = settings.shuffle
        let cmd = PlaybackCommands(settings: settings, controllers: { [] })
        cmd.toggleShuffle()
        XCTAssertEqual(settings.shuffle, !start)
    }

    func testHasActiveSurface_reflectsControllerSet() {
        var set: [VideoPlayerController] = []
        let cmd = PlaybackCommands(settings: makeSettings(), controllers: { set })
        XCTAssertFalse(cmd.hasActiveSurface)
        set = [makeController()]
        XCTAssertTrue(cmd.hasActiveSurface)
    }

    func testStopAndTogglePresentation_invokeSurfaceHooks() {
        let cmd = PlaybackCommands(settings: makeSettings(), controllers: { [] })
        var stopped = false, toggled = false
        cmd.onStop = { stopped = true }
        cmd.onTogglePresentation = { toggled = true }
        cmd.stop(); cmd.togglePresentation()
        XCTAssertTrue(stopped); XCTAssertTrue(toggled)
    }
}
