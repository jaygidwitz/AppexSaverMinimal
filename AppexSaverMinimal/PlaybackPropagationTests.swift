//
//  PlaybackPropagationTests.swift
//  Surrealism
//

import XCTest
@testable import Surrealism

@MainActor
final class PlaybackPropagationTests: XCTestCase {

    private final class FakeEngine: PlaybackEngine {
        var fadeDurations: [TimeInterval] = []
        var rotations: [(urls: [URL], shuffle: Bool)] = []
        func setFadeDuration(_ seconds: TimeInterval) { fadeDurations.append(seconds) }
        func setRotation(_ urls: [URL], shuffle: Bool) { rotations.append((urls, shuffle)) }
    }

    private func makeSettings() -> PlaybackSettings {
        PlaybackSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }
    private func url(_ n: String) -> URL {
        URL(fileURLWithPath: "/Users/Shared/AppexSaverMinimal/videos/\(n).mp4")
    }

    func testInit_noInvocation() {
        let engine = FakeEngine()
        _ = PlaybackPropagator(settings: makeSettings(), engine: engine, library: { [] })
        XCTAssertTrue(engine.fadeDurations.isEmpty, "initial values must be dropped")
        XCTAssertTrue(engine.rotations.isEmpty)
    }

    func testCrossFadeChange_invokesSetFadeDuration_immediately() {
        let settings = makeSettings(); let engine = FakeEngine()
        let prop = PlaybackPropagator(settings: settings, engine: engine, library: { [] })
        settings.setCrossFadeSeconds(2.5)
        XCTAssertEqual(engine.fadeDurations.last, 2.5)
        _ = prop
    }

    func testRotationChange_debounced_invokesSetRotationWithResolvedURLs() {
        let settings = makeSettings(); let engine = FakeEngine()
        let lib = [url("loop-01"), url("loop-02"), url("loop-03")]
        let prop = PlaybackPropagator(settings: settings, engine: engine, library: { lib })
        settings.setRotation(["loop-02"])
        let exp = expectation(description: "debounced rotation fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertEqual(engine.rotations.last?.urls, [self.url("loop-02")])
            XCTAssertEqual(engine.rotations.last?.shuffle, settings.shuffle)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        _ = prop
    }

    func testRapidRotationEdits_debounceToOneRebuild() {
        let settings = makeSettings(); let engine = FakeEngine()
        let lib = [url("loop-01"), url("loop-02")]
        let prop = PlaybackPropagator(settings: settings, engine: engine, library: { lib })
        settings.toggle("loop-01"); settings.toggle("loop-02"); settings.toggle("loop-01")
        let exp = expectation(description: "debounced")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertEqual(engine.rotations.count, 1, "rapid edits collapse to one rebuild")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        _ = prop
    }
}
