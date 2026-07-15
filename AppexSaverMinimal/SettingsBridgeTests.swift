//
//  SettingsBridgeTests.swift
//  Surrealism
//

import XCTest
@testable import Surrealism

final class SettingsBridgeTests: XCTestCase {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bridge-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("playback.json")
    }

    // MARK: Snapshot codec

    func testRoundtrip_preservesAllFields() throws {
        let snap = PlaybackSnapshot(shuffle: false,
                                    crossFadeSeconds: 2.5,
                                    rotation: ["loop-02", "loop-07"],
                                    playbackRate: 0.5)
        let data = try SettingsBridge.encode(snap)
        XCTAssertEqual(SettingsBridge.decode(data), snap)
    }

    func testDecode_clampsOutOfRangeValues() throws {
        let json = #"{"version":1,"shuffle":true,"crossFadeSeconds":99,"rotation":[],"playbackRate":0.01}"#
        let snap = SettingsBridge.decode(Data(json.utf8))
        XCTAssertEqual(snap?.crossFadeSeconds, SettingsBridge.fadeRange.upperBound)
        XCTAssertEqual(snap?.playbackRate, SettingsBridge.rateRange.lowerBound)
    }

    func testDecode_missingKeysFallBackToDefaults() throws {
        let json = #"{"version":1}"#
        let snap = SettingsBridge.decode(Data(json.utf8))
        XCTAssertEqual(snap, PlaybackSnapshot())
        XCTAssertEqual(snap?.shuffle, true)
        XCTAssertEqual(snap?.crossFadeSeconds, SettingsBridge.defaultFade)
        XCTAssertEqual(snap?.rotation, [])
        XCTAssertEqual(snap?.playbackRate, SettingsBridge.defaultRate)
    }

    func testDecode_corruptData_returnsNil() {
        XCTAssertNil(SettingsBridge.decode(Data("not json".utf8)))
    }

    // MARK: File I/O

    func testRead_missingFile_returnsNil() {
        XCTAssertNil(SettingsBridge.read(from: tempFile()))
    }

    func testWriteThenRead_roundtrips_andCreatesDirectory() {
        let url = tempFile()
        let snap = PlaybackSnapshot(shuffle: false, crossFadeSeconds: 3,
                                    rotation: ["loop-01"], playbackRate: 0.75)
        SettingsBridge.write(snap, to: url)
        XCTAssertEqual(SettingsBridge.read(from: url), snap)
    }

    func testWrite_setsWorldReadablePermissions() throws {
        let url = tempFile()
        SettingsBridge.write(PlaybackSnapshot(), to: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        // The sandboxed extension runs as another process and must read this.
        XCTAssertEqual(perms & 0o004, 0o004, "file must be world-readable, got \(String(perms, radix: 8))")
    }

    func testWrite_overwritesExisting() {
        let url = tempFile()
        SettingsBridge.write(PlaybackSnapshot(shuffle: true, crossFadeSeconds: 1,
                                              rotation: [], playbackRate: 1), to: url)
        let second = PlaybackSnapshot(shuffle: false, crossFadeSeconds: 2,
                                      rotation: ["loop-03"], playbackRate: 0.5)
        SettingsBridge.write(second, to: url)
        XCTAssertEqual(SettingsBridge.read(from: url), second)
    }

    // MARK: Shared constants

    func testPlaybackSettingsRangesAliasTheBridge() {
        // One source of truth for clamps: both processes must agree.
        XCTAssertEqual(PlaybackSettings.fadeRange, SettingsBridge.fadeRange)
        XCTAssertEqual(PlaybackSettings.rateRange, SettingsBridge.rateRange)
        XCTAssertEqual(PlaybackSettings.defaultFade, SettingsBridge.defaultFade)
        XCTAssertEqual(PlaybackSettings.defaultRate, SettingsBridge.defaultRate)
    }
}
