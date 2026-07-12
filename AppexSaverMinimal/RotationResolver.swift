//
//  RotationResolver.swift
//  Surrealism
//
//  Turns the persisted rotation selection (a set of stable loop identifiers) into
//  the ordered list of local URLs to play, resolved against the current library.
//  Pure — no AVFoundation — so it's fully unit-testable. See plan U2.
//

import Foundation

enum RotationResolver {
    /// The stable identifier for a loop URL: its filename without extension.
    /// Downloaded catalog loops are `<loopId>.mp4`; user-imported files keep their
    /// own stem. Rotation is persisted by this identifier so it survives the
    /// library changing.
    static func identifier(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Resolve `rotation` against `library` to the ordered URLs to play.
    /// - Empty selection → the whole library ("all loops").
    /// - Identifiers whose file is no longer present are dropped.
    /// - If the selection resolves to nothing (every chosen loop is gone),
    ///   fall back to the full library rather than playing nothing.
    static func activeURLs(rotation: Set<String>, library: [URL]) -> [URL] {
        guard !rotation.isEmpty else { return library }
        let filtered = library.filter { rotation.contains(identifier(for: $0)) }
        return filtered.isEmpty ? library : filtered
    }
}
