//
//  SettingsBridgeWriterTests.swift
//  Surrealism
//

import XCTest
@testable import Surrealism

@MainActor
final class SettingsBridgeWriterTests: XCTestCase {

    private func makeSettings() -> PlaybackSettings {
        PlaybackSettings(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    func testInit_writesCurrentSettingsOnce() {
        let settings = makeSettings()
        settings.setShuffle(false)
        settings.setCrossFadeSeconds(2)
        settings.setRotation(["loop-05"])
        settings.setPlaybackRate(0.5)

        var written: [PlaybackSnapshot] = []
        let writer = SettingsBridgeWriter(settings: settings) { written.append($0) }
        XCTAssertEqual(written.count, 1, "file must exist before any change")
        XCTAssertEqual(written.first, PlaybackSnapshot(shuffle: false, crossFadeSeconds: 2,
                                                       rotation: ["loop-05"], playbackRate: 0.5))
        _ = writer
    }

    func testChange_writesDebouncedSnapshot() {
        let settings = makeSettings()
        var written: [PlaybackSnapshot] = []
        let writer = SettingsBridgeWriter(settings: settings) { written.append($0) }

        settings.setCrossFadeSeconds(3.5)
        let exp = expectation(description: "debounced write fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertEqual(written.last?.crossFadeSeconds, 3.5)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        _ = writer
    }

    func testRapidEdits_collapseToOneWrite() {
        let settings = makeSettings()
        var written: [PlaybackSnapshot] = []
        let writer = SettingsBridgeWriter(settings: settings) { written.append($0) }

        settings.setShuffle(false)
        settings.setRotation(["loop-01", "loop-02"])
        settings.setPlaybackRate(0.75)
        let exp = expectation(description: "debounced")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            XCTAssertEqual(written.count, 2, "init write + one debounced write, got \(written.count)")
            XCTAssertEqual(written.last, PlaybackSnapshot(shuffle: false, crossFadeSeconds: PlaybackSettings.defaultFade,
                                                          rotation: ["loop-01", "loop-02"], playbackRate: 0.75))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        _ = writer
    }

    func testRotationSerializedSorted_forStableFileDiffs() {
        let settings = makeSettings()
        settings.setRotation(["loop-09", "loop-01", "loop-05"])
        var written: [PlaybackSnapshot] = []
        _ = SettingsBridgeWriter(settings: settings) { written.append($0) }
        XCTAssertEqual(written.first?.rotation, ["loop-01", "loop-05", "loop-09"])
    }
}
