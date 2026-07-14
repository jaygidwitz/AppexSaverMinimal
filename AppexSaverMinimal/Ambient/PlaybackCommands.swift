//
//  PlaybackCommands.swift
//  Surrealism · Ambient
//
//  One surface-agnostic transport command set (U1). The overlay buttons, the
//  keyboard handler, the main-menu "Playback" group, and the wallpaper menu-bar
//  item all call this — no per-surface control logic (KTD2).
//
//  Transport actions (play/pause, next) fan out to *every* controller in the
//  active surface's set — one for Theater, one-per-display for wallpaper (KTD7) —
//  so multi-display wallpaper stays in sync. Settings actions (shuffle,
//  cross-fade) mutate the shared PlaybackSettings; the PlaybackPropagator applies
//  them to the running engine. Play/pause is owned here (the controller's own
//  `paused` is private and per-surface), so the command layer is the source of
//  truth for the desired transport state.
//

import Foundation

@MainActor
final class PlaybackCommands {
    private let settings: PlaybackSettings
    /// The active surface's controller set (may be empty when nothing is playing).
    private let controllers: () -> [VideoPlayerController]

    /// Surface-provided hooks for actions only the presenting surface can do.
    var onTogglePresentation: (() -> Void)?
    var onStop: (() -> Void)?

    /// Desired transport state, owned here (see file note). Starts playing.
    private(set) var isPlaying = true

    /// How much one `[` / `]` press moves the cross-fade, in seconds.
    static let crossFadeStepSeconds = 0.2

    init(settings: PlaybackSettings, controllers: @escaping () -> [VideoPlayerController]) {
        self.settings = settings
        self.controllers = controllers
    }

    /// True when a surface is presenting — drives menu-item enablement (U1).
    var hasActiveSurface: Bool { !controllers().isEmpty }

    func playPause() {
        isPlaying.toggle()
        let set = controllers()
        if isPlaying { set.forEach { $0.resume() } } else { set.forEach { $0.pause() } }
    }

    func next() { controllers().forEach { $0.skip() } }

    func toggleShuffle() { settings.setShuffle(!settings.shuffle) }

    /// Nudge the shared cross-fade; `setCrossFadeSeconds` clamps to `fadeRange`.
    func crossFadeStep(_ direction: Int) {
        settings.setCrossFadeSeconds(settings.crossFadeSeconds + Double(direction) * Self.crossFadeStepSeconds)
    }

    func togglePresentation() { onTogglePresentation?() }
    func stop() { onStop?() }
}
