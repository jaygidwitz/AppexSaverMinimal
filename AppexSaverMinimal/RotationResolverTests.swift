//
//  RotationResolverTests.swift
//  Surrealism
//

import XCTest
@testable import Surrealism

final class RotationResolverTests: XCTestCase {
    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Users/Shared/AppexSaverMinimal/videos/\(name)")
    }
    private lazy var library = ["loop-01.mp4", "loop-05.mp4", "my clip.mov", "loop-12.mp4"].map(url)

    func testIdentifier_isFileStem() {
        XCTAssertEqual(RotationResolver.identifier(for: url("loop-12.mp4")), "loop-12")
        XCTAssertEqual(RotationResolver.identifier(for: url("my clip.mov")), "my clip")
    }

    func testEmptyRotation_returnsWholeLibrary() {
        XCTAssertEqual(RotationResolver.activeURLs(rotation: [], library: library), library)
    }

    func testSelection_resolvesToChosenURLsInLibraryOrder() {
        let out = RotationResolver.activeURLs(rotation: ["loop-05", "loop-12"], library: library)
        XCTAssertEqual(out, [url("loop-05.mp4"), url("loop-12.mp4")])
    }

    func testUserImportedFile_resolvesByStem() {
        let out = RotationResolver.activeURLs(rotation: ["my clip"], library: library)
        XCTAssertEqual(out, [url("my clip.mov")])
    }

    func testMissingIdsDropped_butPresentOnesKept() {
        let out = RotationResolver.activeURLs(rotation: ["loop-01", "loop-99-gone"], library: library)
        XCTAssertEqual(out, [url("loop-01.mp4")])
    }

    func testAllSelectedMissing_fallsBackToWholeLibrary() {
        let out = RotationResolver.activeURLs(rotation: ["gone-1", "gone-2"], library: library)
        XCTAssertEqual(out, library, "empty result must fall back to all, not play nothing")
    }
}
