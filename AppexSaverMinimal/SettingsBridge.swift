//
//  SettingsBridge.swift
//  Surrealism
//
//  The screensaver control-bridge (deferred R7): the host serializes the shared
//  playback settings to a world-readable JSON file next to the video cache; the
//  sandboxed extension reads it on launch and applies rotation/shuffle/fade/speed.
//  The appex runs in a separate process with no IPC surface, so settings apply on
//  the screensaver's NEXT start — never live.
//
//  Compiled into BOTH targets (host + extension), like VideoPlayerController —
//  see CLAUDE.md on dual target membership. Keep it dependency-free.
//

import Foundation

/// One serialized frame of the shared playback settings. Decoding is
/// forward-tolerant: missing keys fall back to defaults, out-of-range values
/// are clamped, so an older extension can read a newer host's file.
struct PlaybackSnapshot: Codable, Equatable {
    var version: Int = 1
    var shuffle: Bool = true
    var crossFadeSeconds: Double = SettingsBridge.defaultFade
    var rotation: [String] = []
    var playbackRate: Double = SettingsBridge.defaultRate

    init(shuffle: Bool = true,
         crossFadeSeconds: Double = SettingsBridge.defaultFade,
         rotation: [String] = [],
         playbackRate: Double = SettingsBridge.defaultRate) {
        self.shuffle = shuffle
        self.crossFadeSeconds = SettingsBridge.clampFade(crossFadeSeconds)
        self.rotation = rotation
        self.playbackRate = SettingsBridge.clampRate(playbackRate)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        shuffle = try c.decodeIfPresent(Bool.self, forKey: .shuffle) ?? true
        crossFadeSeconds = SettingsBridge.clampFade(
            try c.decodeIfPresent(Double.self, forKey: .crossFadeSeconds) ?? SettingsBridge.defaultFade)
        rotation = try c.decodeIfPresent([String].self, forKey: .rotation) ?? []
        playbackRate = SettingsBridge.clampRate(
            try c.decodeIfPresent(Double.self, forKey: .playbackRate) ?? SettingsBridge.defaultRate)
    }
}

enum SettingsBridge {
    /// Accepted ranges + defaults live here — the one source of truth both
    /// processes share. `PlaybackSettings` (host-only) re-exports them.
    static let fadeRange: ClosedRange<Double> = 0.2...5.0
    static let defaultFade: Double = 1.4
    static let rateRange: ClosedRange<Double> = 0.25...1.0
    static let defaultRate: Double = 1.0

    /// Next to the video cache, same world-readable contract (see LoopDownloader).
    static let fileURL = URL(fileURLWithPath: "/Users/Shared/AppexSaverMinimal/playback.json")

    static func clampFade(_ v: Double) -> Double {
        min(max(v, fadeRange.lowerBound), fadeRange.upperBound)
    }

    static func clampRate(_ v: Double) -> Double {
        min(max(v, rateRange.lowerBound), rateRange.upperBound)
    }

    // MARK: Codec (pure, unit-tested)

    static func encode(_ snapshot: PlaybackSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// nil on corrupt data — the extension then behaves as if no file existed.
    static func decode(_ data: Data) -> PlaybackSnapshot? {
        try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }

    // MARK: File I/O

    /// Best-effort atomic write, explicitly world-readable: the sandboxed
    /// extension runs as another process and must be able to read what the
    /// host wrote (the same 0o644 rule as the video cache).
    static func write(_ snapshot: PlaybackSnapshot, to url: URL = fileURL) {
        guard let data = try? encode(snapshot) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    /// nil when the file is missing or unreadable/corrupt.
    static func read(from url: URL = fileURL) -> PlaybackSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
}
