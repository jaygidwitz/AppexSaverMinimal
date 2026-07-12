//
//  VideoPlayerControllerTests.swift
//  Surrealism
//
//  Pure-logic coverage for the live-control API (U3). AVFoundation playback,
//  cross-fade timing, and observer teardown are verified by manual soak per the
//  plan; these tests cover the playlist/guard logic that is deterministic.
//

import XCTest
import AVFoundation
@testable import Surrealism

final class VideoPlayerControllerTests: XCTestCase {
    private func urls(_ n: Int) -> [URL] {
        (1...n).map { URL(fileURLWithPath: "/tmp/loop-\($0).mp4") }
    }

    func testInit_shuffleFalse_preservesOrder() {
        let vpc = VideoPlayerController(videos: urls(3), shuffle: false)
        XCTAssertEqual(vpc.testPlaylist, urls(3))
    }

    func testInit_shuffleTrue_isPermutationOfSameSet() {
        let vpc = VideoPlayerController(videos: urls(6), shuffle: true)
        XCTAssertEqual(Set(vpc.testPlaylist), Set(urls(6)))
        XCTAssertEqual(vpc.testPlaylist.count, 6)
    }

    func testSetRotation_notStarted_swapsPlaylist() {
        let vpc = VideoPlayerController(videos: urls(4), shuffle: false)
        vpc.setRotation(urls(2), shuffle: false)
        XCTAssertEqual(vpc.testPlaylist, urls(2))
    }

    func testSetRotation_shuffleFalse_preservesOrder_shuffleTrue_permutes() {
        let vpc = VideoPlayerController(videos: urls(1), shuffle: false)
        vpc.setRotation(urls(5), shuffle: false)
        XCTAssertEqual(vpc.testPlaylist, urls(5))
        vpc.setRotation(urls(5), shuffle: true)
        XCTAssertEqual(Set(vpc.testPlaylist), Set(urls(5)))
    }

    func testSetFadeDuration_updates() {
        let vpc = VideoPlayerController(videos: urls(2))
        vpc.setFadeDuration(3.0)
        XCTAssertEqual(vpc.testFadeDuration, 3.0, accuracy: 0.0001)
    }

    func testSkipBeforeStart_isNoOp_noCrash() {
        let vpc = VideoPlayerController(videos: urls(2))
        vpc.skip() // not started → guard returns; must not crash
        XCTAssertEqual(vpc.testPlaylist.count, 2)
    }

    func testPauseResume_beforeStart_noCrash() {
        let vpc = VideoPlayerController(videos: urls(2))
        vpc.pause()
        vpc.resume()
    }

    func testHasVideos() {
        XCTAssertTrue(VideoPlayerController(videos: urls(1)).hasVideos)
        XCTAssertFalse(VideoPlayerController(videos: []).hasVideos)
    }
}
