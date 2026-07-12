//
//  PlaybackPropagation.swift
//  Surrealism
//
//  Pushes shared-settings changes into a running player (R6): a cross-fade change
//  re-times transitions immediately; a rotation/shuffle change swaps the playing
//  set (debounced so a slider/selection drag doesn't rebuild on every tick). The
//  engine is behind a protocol so this is unit-testable with a fake. See plan U6.
//

import Foundation
import Combine

/// The slice of VideoPlayerController that live settings drive.
protocol PlaybackEngine: AnyObject {
    func setFadeDuration(_ seconds: TimeInterval)
    func setRotation(_ urls: [URL], shuffle: Bool)
}

extension VideoPlayerController: PlaybackEngine {}

@MainActor
final class PlaybackPropagator {
    private var bag = Set<AnyCancellable>()

    /// - Parameter library: evaluated on each rotation change so the resolver sees
    ///   the current library.
    init(settings: PlaybackSettings, engine: PlaybackEngine, library: @escaping () -> [URL]) {
        // Cross-fade applies continuously (the engine reads it live per tick).
        settings.$crossFadeSeconds
            .dropFirst()
            .sink { engine.setFadeDuration($0) }
            .store(in: &bag)

        // Rotation + shuffle rebuild the playlist — debounced to one rebuild per
        // burst of edits (dragging a selection shouldn't rebuild on every change).
        // CombineLatest emits one initial (dropped) value, then on either change.
        Publishers.CombineLatest(settings.$rotation, settings.$shuffle)
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak settings] _ in
                guard let settings else { return }
                let urls = RotationResolver.activeURLs(rotation: settings.rotation, library: library())
                engine.setRotation(urls, shuffle: settings.shuffle)
            }
            .store(in: &bag)
    }
}
