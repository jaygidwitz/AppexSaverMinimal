//
//  AppexSaverMinimalView.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  ScreenSaverView that displays the rainbow color animation, OR — as of the
//  U12 risk-retirement spike — plays the first video found in the shared cache
//  at /Users/Shared/AppexSaverMinimal/videos.
//
//  ⚠️ U12 SPIKE SCAFFOLDING. The video path below is intentionally minimal: it
//  exists only to prove that a *notarized, sandboxed* extension can read a
//  world-readable file from /Users/Shared at the login window / lock screen.
//  It will be replaced by the real shared VideoPlayerController (U1) reading
//  through VideoCache (U2), wired in via U3. Do not build on it.
//

import ScreenSaver
import QuartzCore
import AVFoundation

private let logger = AppexLog.logger("View")

final class AppexSaverMinimalView: ScreenSaverView {

    private let animator = RainbowAnimator()

    // MARK: - U12 spike: shared-cache video playback
    private static let spikeCacheDirectory = "/Users/Shared/AppexSaverMinimal/videos"
    private var playerLayer: AVPlayerLayer?
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    override init?(frame: NSRect, isPreview: Bool) {
        logger.info("init(frame: \(frame.size.width, privacy: .public)x\(frame.size.height, privacy: .public), isPreview: \(isPreview))")
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        animationTimeInterval = 1.0 / 60.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    deinit {
        animator.stop()
        teardownVideo()
        logger.info("deinit")
    }

    // MARK: - Layer Setup

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = animator.currentBackgroundColor.cgColor
        layer.isOpaque = true
        return layer
    }

    // MARK: - ScreenSaverView Overrides
    //
    // These are called by the framework. We rely on viewDidMoveToWindow to
    // start/stop rendering (robust across both ScreenSaverEngine and System
    // Settings preview), but the overrides remain so the framework can drive
    // them if it wants to.

    override func startAnimation() {
        logger.info("startAnimation()")
        super.startAnimation()
        animator.start()
    }

    override func stopAnimation() {
        logger.info("stopAnimation()")
        animator.stop()
        super.stopAnimation()
    }

    // MARK: - View Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        logger.info("viewDidMoveToWindow() hasWindow=\(self.window != nil)")

        guard self.window != nil, let layer = self.layer else {
            animator.stop()
            teardownVideo()
            return
        }

        // U12 spike: prefer a cached video; fall back to the rainbow if none.
        if let videoURL = Self.firstCachedVideoURL() {
            logger.info("U12 spike: playing cached video \(videoURL.lastPathComponent, privacy: .public)")
            animator.stop()
            setupVideo(url: videoURL, in: layer)
        } else {
            logger.info("U12 spike: no cached video found at \(Self.spikeCacheDirectory, privacy: .public); using rainbow fallback")
            teardownVideo()
            animator.attach(to: layer)
            animator.updateBounds(bounds)
            animator.start()
        }
    }

    override func layout() {
        super.layout()
        animator.updateBounds(bounds)
        playerLayer?.frame = bounds
    }

    // MARK: - U12 spike helpers

    /// Returns the first playable file in the shared cache directory, or nil.
    private static func firstCachedVideoURL() -> URL? {
        let dir = URL(fileURLWithPath: spikeCacheDirectory, isDirectory: true)
        let exts: Set<String> = ["mp4", "mov", "m4v"]
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: spikeCacheDirectory) else {
            return nil
        }
        return names
            .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .first
            .map { dir.appendingPathComponent($0) }
    }

    private func setupVideo(url: URL, in layer: CALayer) {
        teardownVideo()

        layer.backgroundColor = NSColor.black.cgColor
        layer.isOpaque = true

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: item)

        let pLayer = AVPlayerLayer(player: player)
        pLayer.frame = bounds
        pLayer.videoGravity = .resizeAspectFill
        pLayer.backgroundColor = NSColor.black.cgColor
        layer.addSublayer(pLayer)

        queuePlayer = player
        playerLayer = pLayer
        player.play()
    }

    private func teardownVideo() {
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        queuePlayer = nil
    }
}
