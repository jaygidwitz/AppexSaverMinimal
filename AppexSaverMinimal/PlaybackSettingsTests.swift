//
//  PlaybackSettingsTests.swift
//  Surrealism
//
//  Round-trip persistence + clamping for the shared playback settings store.
//  Runs in AppexSaverMinimalTests:
//    xcodebuild test -scheme AppexSaverMinimal -destination 'platform=macOS'
//

import XCTest
@testable import Surrealism

@MainActor
final class PlaybackSettingsTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    func testDefaults_freshStore() {
        let store = PlaybackSettings(defaults: makeDefaults())
        XCTAssertTrue(store.shuffle, "shuffle defaults on")
        XCTAssertEqual(store.crossFadeSeconds, PlaybackSettings.defaultFade, accuracy: 0.0001)
        XCTAssertTrue(store.rotation.isEmpty, "empty rotation = all loops")
    }

    func testSetters_updatePublishedAndPersist() {
        let defaults = makeDefaults()
        let store = PlaybackSettings(defaults: defaults)
        store.setShuffle(false)
        store.setCrossFadeSeconds(3.0)
        store.setRotation(["loop-01", "loop-05"])
        XCTAssertFalse(store.shuffle)
        XCTAssertEqual(store.crossFadeSeconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(store.rotation, ["loop-01", "loop-05"])
    }

    func testRoundTrip_secondStoreReadsPersistedValues() {
        let defaults = makeDefaults()
        let a = PlaybackSettings(defaults: defaults)
        a.setShuffle(false)
        a.setCrossFadeSeconds(2.5)
        a.setRotation(["loop-09"])

        let b = PlaybackSettings(defaults: defaults)
        XCTAssertFalse(b.shuffle)
        XCTAssertEqual(b.crossFadeSeconds, 2.5, accuracy: 0.0001)
        XCTAssertEqual(b.rotation, ["loop-09"])
    }

    func testCrossFade_clampsOutOfRange() {
        let store = PlaybackSettings(defaults: makeDefaults())
        store.setCrossFadeSeconds(99)
        XCTAssertEqual(store.crossFadeSeconds, PlaybackSettings.fadeRange.upperBound, accuracy: 0.0001)
        store.setCrossFadeSeconds(-5)
        XCTAssertEqual(store.crossFadeSeconds, PlaybackSettings.fadeRange.lowerBound, accuracy: 0.0001)
    }

    func testStoredCrossFade_clampedOnLoad() {
        let defaults = makeDefaults()
        defaults.set(42.0, forKey: "app.surrealism.playback.crossFade") // out-of-range legacy value
        let store = PlaybackSettings(defaults: defaults)
        XCTAssertEqual(store.crossFadeSeconds, PlaybackSettings.fadeRange.upperBound, accuracy: 0.0001)
    }

    func testToggle_addsAndRemoves() {
        let store = PlaybackSettings(defaults: makeDefaults())
        store.toggle("loop-01")
        XCTAssertEqual(store.rotation, ["loop-01"])
        store.toggle("loop-02")
        XCTAssertEqual(store.rotation, ["loop-01", "loop-02"])
        store.toggle("loop-01")
        XCTAssertEqual(store.rotation, ["loop-02"])
    }

    func testEmptyRotation_persistsAndReloadsEmpty() {
        let defaults = makeDefaults()
        let a = PlaybackSettings(defaults: defaults)
        a.setRotation(["loop-01"])
        a.setRotation([]) // back to "all"
        let b = PlaybackSettings(defaults: defaults)
        XCTAssertTrue(b.rotation.isEmpty)
    }

    // MARK: - setSelected (tile picker, U1)

    private let all3 = ["loop-01", "loop-02", "loop-03"]

    func testSetSelected_deselectFromAll_materializesAllMinusOne() {
        let store = PlaybackSettings(defaults: makeDefaults())
        // Fresh store is empty = all.
        store.setSelected("loop-02", isOn: false, allIdentifiers: all3)
        XCTAssertEqual(store.rotation, ["loop-01", "loop-03"])
    }

    func testSetSelected_selectLast_collapsesToEmptySentinel() {
        let store = PlaybackSettings(defaults: makeDefaults())
        store.setRotation(["loop-01", "loop-03"])
        store.setSelected("loop-02", isOn: true, allIdentifiers: all3)
        XCTAssertTrue(store.rotation.isEmpty, "covers all ⇒ collapse to sentinel")
    }

    func testSetSelected_partialDeselect_staysPartial() {
        let store = PlaybackSettings(defaults: makeDefaults())
        store.setRotation(["loop-01", "loop-02"])
        store.setSelected("loop-01", isOn: false, allIdentifiers: all3)
        XCTAssertEqual(store.rotation, ["loop-02"])
    }

    func testSetSelected_oneLoopFloor_isNoOp() {
        let store = PlaybackSettings(defaults: makeDefaults())
        store.setRotation(["loop-02"])
        store.setSelected("loop-02", isOn: false, allIdentifiers: all3)
        XCTAssertEqual(store.rotation, ["loop-02"], "cannot deselect the last loop (R6)")
    }

    func testSetSelected_floorFromAllReachesOneNotZero() {
        let store = PlaybackSettings(defaults: makeDefaults()) // empty = all
        store.setSelected("loop-01", isOn: false, allIdentifiers: all3)
        store.setSelected("loop-02", isOn: false, allIdentifiers: all3)
        XCTAssertEqual(store.rotation, ["loop-03"])
        store.setSelected("loop-03", isOn: false, allIdentifiers: all3) // floor
        XCTAssertEqual(store.rotation, ["loop-03"], "never empties to zero loops")
    }

    func testIsAllSelected_reflectsCoverage() {
        let store = PlaybackSettings(defaults: makeDefaults())
        XCTAssertTrue(store.isAllSelected(allIdentifiers: all3), "empty = all")
        store.setRotation(["loop-01", "loop-02", "loop-03"])
        XCTAssertTrue(store.isAllSelected(allIdentifiers: all3), "lists every current id")
        store.setRotation(["loop-01"])
        XCTAssertFalse(store.isAllSelected(allIdentifiers: all3), "strict subset")
    }

    func testIsAllSelected_staleIdsDoNotCountAsAll() {
        let store = PlaybackSettings(defaults: makeDefaults())
        store.setRotation(["loop-01", "gone-99"])
        XCTAssertFalse(store.isAllSelected(allIdentifiers: ["loop-01", "loop-02"]))
    }

    func testSetSelected_persistsNormalizedSet() {
        let defaults = makeDefaults()
        let a = PlaybackSettings(defaults: defaults)
        a.setSelected("loop-02", isOn: false, allIdentifiers: all3) // → {01,03}
        let b = PlaybackSettings(defaults: defaults)
        XCTAssertEqual(b.rotation, ["loop-01", "loop-03"])
    }
}
