//
//  SettingsBridgeWriter.swift
//  Surrealism
//
//  Host-only companion to SettingsBridge: mirrors PlaybackPropagator, but instead
//  of steering a live engine it re-serializes the settings file the screensaver
//  reads on its next launch. Writes once at init (so the file exists before any
//  change) and then debounces edits so a slider drag doesn't rewrite per tick.
//

import Foundation
import Combine

@MainActor
final class SettingsBridgeWriter {
    private var bag = Set<AnyCancellable>()

    init(settings: PlaybackSettings,
         write: @escaping (PlaybackSnapshot) -> Void = { SettingsBridge.write($0) }) {
        write(Self.snapshot(of: settings))

        Publishers.CombineLatest4(settings.$shuffle,
                                  settings.$crossFadeSeconds,
                                  settings.$rotation,
                                  settings.$playbackRate)
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { shuffle, fade, rotation, rate in
                write(PlaybackSnapshot(shuffle: shuffle,
                                       crossFadeSeconds: fade,
                                       rotation: rotation.sorted(),
                                       playbackRate: rate))
            }
            .store(in: &bag)
    }

    /// Rotation is serialized sorted so the on-disk file is deterministic.
    private static func snapshot(of settings: PlaybackSettings) -> PlaybackSnapshot {
        PlaybackSnapshot(shuffle: settings.shuffle,
                         crossFadeSeconds: settings.crossFadeSeconds,
                         rotation: settings.rotation.sorted(),
                         playbackRate: settings.playbackRate)
    }
}
