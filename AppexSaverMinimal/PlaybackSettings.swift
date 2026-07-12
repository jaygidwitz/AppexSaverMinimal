//
//  PlaybackSettings.swift
//  Surrealism
//
//  The shared, persisted source of truth for playback controls (R5/R8): shuffle,
//  cross-fade duration, and which loops are in rotation. Mirrors LicenseStore —
//  a @MainActor ObservableObject with UserDefaults injected for persistence and
//  testability. App-owned (AppDelegate) and injected via .environmentObject so a
//  change is observed everywhere; the in-app player propagates it live (U6).
//
//  Settings are global for v1 (one shared rotation/shuffle/cross-fade), not
//  per-surface. The store is shaped so it can later serialize to a /Users/Shared
//  config file the sandboxed screensaver reads on launch (deferred bridge, R7).
//

import Foundation

@MainActor
final class PlaybackSettings: ObservableObject {
    /// Shuffle on = randomized order; off = in-order (R5).
    @Published private(set) var shuffle: Bool
    /// Cross-fade duration in seconds, clamped to `fadeRange`.
    @Published private(set) var crossFadeSeconds: Double
    /// The loops in rotation, by stable identifier (file stem). Empty = all loops.
    @Published private(set) var rotation: Set<String>

    /// Accepted cross-fade range; the effective fade is additionally clamped
    /// against the current clip's length inside the engine (see VideoPlayerController).
    static let fadeRange: ClosedRange<Double> = 0.2...5.0
    /// Default cross-fade — matches the value the screensaver has always used.
    static let defaultFade: Double = 1.4

    private let defaults: UserDefaults
    private let kShuffle = "app.surrealism.playback.shuffle"
    private let kCrossFade = "app.surrealism.playback.crossFade"
    private let kRotation = "app.surrealism.playback.rotation"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.shuffle = defaults.object(forKey: kShuffle) as? Bool ?? true
        let storedFade = defaults.object(forKey: kCrossFade) as? Double ?? Self.defaultFade
        self.crossFadeSeconds = Self.clampFade(storedFade)
        self.rotation = Set(defaults.stringArray(forKey: kRotation) ?? [])
    }

    func setShuffle(_ on: Bool) {
        shuffle = on
        defaults.set(on, forKey: kShuffle)
    }

    /// Clamps to `fadeRange` before storing — the UI slider and any external
    /// caller can pass a raw value.
    func setCrossFadeSeconds(_ seconds: Double) {
        let clamped = Self.clampFade(seconds)
        crossFadeSeconds = clamped
        defaults.set(clamped, forKey: kCrossFade)
    }

    /// Replace the rotation selection. An empty set means "all loops".
    func setRotation(_ ids: Set<String>) {
        rotation = ids
        defaults.set(Array(ids), forKey: kRotation)
    }

    /// Add/remove one loop from the rotation (for the multi-select picker).
    func toggle(_ id: String) {
        var next = rotation
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        setRotation(next)
    }

    private static func clampFade(_ v: Double) -> Double {
        min(max(v, fadeRange.lowerBound), fadeRange.upperBound)
    }
}
