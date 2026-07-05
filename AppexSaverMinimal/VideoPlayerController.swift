//
//  VideoPlayerController.swift
//  AppexSaverMinimal
//
//  Copyright © 2026. Licensed under the MIT License.
//
//  Shared video playback engine used by BOTH the screensaver extension
//  (AppexSaverMinimalView) and the host app's preview (PreviewView), so the two
//  render identically. Mirrors the dual-target-membership pattern of
//  RainbowAnimator (see CLAUDE.md): this file physically lives in the host-app
//  folder but is compiled into both targets.
//
//  Playback model (see docs/plans/2026-07-05-001-feat-video-screensaver-plan.md,
//  KTD "Multi-clip rotation via observe-end + cross-fade"):
//    - One clip  -> AVPlayerLooper (gapless at rate 1.0).
//    - Many clips -> reuse a single AVQueuePlayer, observe end-of-item, swap the
//      item, and mask the boundary with an opacity fade on the AVPlayerLayer.
//  A single AVQueuePlayer is reused for the controller's lifetime (never a new
//  player per clip) and every observer is torn down on each transition to avoid
//  the memory creep / double-fire that plague AVPlayer rotation.
//

import AppKit
import AVFoundation
import QuartzCore

/// Resolves the shared, world-readable video cache both the host app writes to
/// and the sandboxed extension reads from (see plan KTD "Cache in /Users/Shared").
enum VideoCache {
    static let directory = "/Users/Shared/AppexSaverMinimal/videos"

    /// Playable video files currently in the cache, sorted deterministically.
    static func videos() -> [URL] {
        let exts: Set<String> = ["mp4", "mov", "m4v"]
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        return names
            .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { base.appendingPathComponent($0) }
    }
}

final class VideoPlayerController {

    private let playlist: [URL]
    private let fadeDuration: TimeInterval = 1.2

    private let queuePlayer = AVQueuePlayer()
    private var playerLayer: AVPlayerLayer?
    private weak var parentLayer: CALayer?

    private var looper: AVPlayerLooper?            // single-clip path only
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var wakeObserver: NSObjectProtocol?

    private var index = 0
    private var isFadingOut = false
    private var started = false

    /// `true` when there is at least one playable video.
    var hasVideos: Bool { !playlist.isEmpty }

    init(videos: [URL], shuffle: Bool = true) {
        self.playlist = shuffle ? videos.shuffled() : videos
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
    }

    deinit { stop() }

    // MARK: - Attachment

    /// Creates the AVPlayerLayer and inserts it at the bottom of `layer`.
    func attach(to layer: CALayer) {
        parentLayer = layer
        layer.backgroundColor = NSColor.black.cgColor
        layer.isOpaque = true

        let pLayer = AVPlayerLayer(player: queuePlayer)
        pLayer.frame = layer.bounds
        pLayer.videoGravity = .resizeAspectFill
        pLayer.backgroundColor = NSColor.black.cgColor
        pLayer.opacity = 0                      // fade the first clip in
        layer.insertSublayer(pLayer, at: 0)
        playerLayer = pLayer
    }

    func updateBounds(_ bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        CATransaction.commit()
    }

    // MARK: - Lifecycle

    func start() {
        guard hasVideos, !started else { return }
        started = true

        installWakeObserver()

        if playlist.count == 1 {
            startSingleClipLoop(playlist[0])
        } else {
            playCurrentItem(fadeIn: true)
        }
    }

    func stop() {
        started = false
        queuePlayer.pause()
        looper?.disableLooping()
        looper = nil
        removeItemObservers()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        queuePlayer.removeAllItems()
    }

    // MARK: - Single clip (gapless loop)

    private func startSingleClipLoop(_ url: URL) {
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.play()
        fade(to: 1)
    }

    // MARK: - Playlist rotation (fade between clips)

    private func playCurrentItem(fadeIn: Bool) {
        removeItemObservers()
        queuePlayer.removeAllItems()

        let url = playlist[index]
        let item = AVPlayerItem(url: url)
        queuePlayer.insert(item, after: nil)

        isFadingOut = false
        playerLayer?.opacity = fadeIn ? 0 : 1
        queuePlayer.play()
        if fadeIn { fade(to: 1) }

        // Advance when this item finishes.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.advance()
        }

        // Start the fade-out during the final `fadeDuration` seconds.
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = queuePlayer.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] _ in
            self?.maybeFadeOut(item)
        }
    }

    private func maybeFadeOut(_ item: AVPlayerItem) {
        guard !isFadingOut, item.status == .readyToPlay else { return }
        let duration = item.duration.seconds
        let current = item.currentTime().seconds
        guard duration.isFinite, duration > 0 else { return }
        if duration - current <= fadeDuration {
            isFadingOut = true
            fade(to: 0)
        }
    }

    private func advance() {
        guard started else { return }
        index = (index + 1) % playlist.count
        playCurrentItem(fadeIn: true)
    }

    // MARK: - Fade helper

    private func fade(to opacity: Float) {
        guard let layer = playerLayer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = opacity
        animation.duration = fadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .forwards
        layer.add(animation, forKey: "fade")
        layer.opacity = opacity
    }

    // MARK: - Observers

    private func removeItemObservers() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let timeObserver {
            queuePlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func installWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.started else { return }
            if self.queuePlayer.currentItem == nil {
                // Queue drained during sleep — restart from the current clip.
                if self.playlist.count == 1 {
                    self.startSingleClipLoop(self.playlist[0])
                } else {
                    self.playCurrentItem(fadeIn: true)
                }
            } else {
                // Nudge the layer so it refreshes on wake.
                self.queuePlayer.pause()
                self.queuePlayer.play()
            }
        }
    }
}
