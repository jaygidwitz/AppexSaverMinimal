//
//  VideoPlayerController.swift
//  AppexSaverMinimal
//
//  Copyright © 2026. Licensed under the MIT License.
//
//  Shared video playback engine used by BOTH the screensaver extension
//  (AppexSaverMinimalView) and the host app's preview (PreviewView). Mirrors the
//  dual-target-membership pattern of RainbowAnimator (see CLAUDE.md).
//
//  Rotation uses a TRUE cross-fade across two AVPlayerLayers: the next clip is
//  brought up on the idle layer and faded in while the current layer fades out,
//  so there is always a frame on screen — no black gap / blink at the boundary.
//  A single clip loops gaplessly via AVPlayerLooper.
//

import AppKit
import AVFoundation
import QuartzCore

/// Resolves the shared, world-readable video cache both the host app writes to
/// and the sandboxed extension reads from (see plan KTD "Cache in /Users/Shared").
enum VideoCache {
    static let directory = "/Users/Shared/AppexSaverMinimal/videos"

    static func videos() -> [URL] {
        let exts: Set<String> = ["mp4", "mov", "m4v"]
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        return names
            .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { base.appendingPathComponent($0) }
    }
}

final class VideoPlayerController {

    private struct Slot {
        let player: AVQueuePlayer
        let layer: AVPlayerLayer
    }

    private let playlist: [URL]
    private let fadeDuration: TimeInterval = 1.4

    private var slots: [Slot] = []
    private var active = 0
    private var index = 0
    private var started = false
    private var transitioning = false

    private var looper: AVPlayerLooper?
    private var timeObserver: Any?
    private var observedPlayer: AVQueuePlayer?
    private var endObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var pendingFinish: DispatchWorkItem?

    var hasVideos: Bool { !playlist.isEmpty }

    init(videos: [URL], shuffle: Bool = true) {
        self.playlist = shuffle ? videos.shuffled() : videos
    }

    deinit { stop() }

    // MARK: - Attachment

    func attach(to layer: CALayer) {
        layer.backgroundColor = NSColor.black.cgColor
        layer.isOpaque = true
        for _ in 0..<2 {
            let player = AVQueuePlayer()
            player.isMuted = true
            player.actionAtItemEnd = .pause
            let pLayer = AVPlayerLayer(player: player)
            pLayer.frame = layer.bounds
            pLayer.videoGravity = .resizeAspectFill
            pLayer.backgroundColor = NSColor.black.cgColor
            pLayer.opacity = 0
            layer.addSublayer(pLayer)
            slots.append(Slot(player: player, layer: pLayer))
        }
    }

    func updateBounds(_ bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slots.forEach { $0.layer.frame = bounds }
        CATransaction.commit()
    }

    // MARK: - Lifecycle

    func start() {
        guard hasVideos, !started, !slots.isEmpty else { return }
        started = true
        installWakeObserver()

        if playlist.count == 1 {
            let slot = slots[active]
            looper = AVPlayerLooper(player: slot.player, templateItem: AVPlayerItem(url: playlist[0]))
            slot.player.play()
            fade(slot.layer, to: 1)
        } else {
            index = 0
            let slot = slots[active]
            load(playlist[index], into: slot)
            slot.player.play()
            fade(slot.layer, to: 1)
            watchForEnd(of: slot)
        }
    }

    func stop() {
        started = false
        transitioning = false
        pendingFinish?.cancel(); pendingFinish = nil
        looper?.disableLooping(); looper = nil
        removeTimeObserver()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver); self.wakeObserver = nil }
        slots.forEach { $0.player.pause(); $0.player.removeAllItems() }
    }

    // MARK: - Rotation with cross-fade

    private func load(_ url: URL, into slot: Slot) {
        slot.player.removeAllItems()
        slot.player.insert(AVPlayerItem(url: url), after: nil)
    }

    /// Watch the active clip and begin the cross-fade `fadeDuration` before it ends
    /// (or immediately if it ends first).
    private func watchForEnd(of slot: Slot) {
        removeTimeObserver()
        observedPlayer = slot.player

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = slot.player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self, self.started, !self.transitioning,
                  let item = slot.player.currentItem, item.status == .readyToPlay else { return }
            let duration = item.duration.seconds
            let current = item.currentTime().seconds
            guard duration.isFinite, duration > 0 else { return }
            if duration - current <= self.fadeDuration {
                self.beginTransition()
            }
        }

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: slot.player.currentItem, queue: .main
        ) { [weak self] _ in
            self?.beginTransition()   // safety: clip shorter than fadeDuration
        }
    }

    private func beginTransition() {
        guard started, !transitioning, playlist.count > 1 else { return }
        transitioning = true
        removeTimeObserver()

        let current = slots[active]
        let next = slots[1 - active]
        let nextIndex = (index + 1) % playlist.count

        load(playlist[nextIndex], into: next)
        next.layer.opacity = 0
        next.player.seek(to: .zero)
        next.player.play()

        // Cross-fade
        fade(next.layer, to: 1)
        fade(current.layer, to: 0)

        let finish = DispatchWorkItem { [weak self] in
            guard let self else { return }
            current.player.pause()
            current.player.removeAllItems()
            self.active = 1 - self.active
            self.index = nextIndex
            self.transitioning = false
            if self.started { self.watchForEnd(of: self.slots[self.active]) }
        }
        pendingFinish = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration, execute: finish)
    }

    // MARK: - Fade

    private func fade(_ layer: CALayer, to opacity: Float) {
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

    private func removeTimeObserver() {
        if let timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        observedPlayer = nil
    }

    private func installWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.started else { return }
            let slot = self.slots[self.active]
            if slot.player.currentItem == nil {
                if self.playlist.count == 1 {
                    self.looper?.disableLooping()
                    self.looper = AVPlayerLooper(player: slot.player, templateItem: AVPlayerItem(url: self.playlist[0]))
                } else {
                    self.load(self.playlist[self.index], into: slot)
                    self.watchForEnd(of: slot)
                }
                slot.player.play()
            } else {
                slot.player.pause(); slot.player.play()   // nudge the layer awake
            }
        }
    }
}
