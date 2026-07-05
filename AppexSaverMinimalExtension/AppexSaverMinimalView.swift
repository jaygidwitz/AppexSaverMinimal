//
//  AppexSaverMinimalView.swift
//  AppexSaverMinimalExtension
//
//  Copyright © 2026. Licensed under the MIT License.
//
//  ScreenSaverView that plays the cached video library via the shared
//  VideoPlayerController (rotating through clips with fade transitions), and
//  falls back to the RainbowAnimator when the cache is empty.
//
//  Lifecycle is driven from viewDidMoveToWindow — in the .appex context
//  startAnimation()/stopAnimation() are not reliably called. SSENeedsAnimationTimer
//  stays false: AVPlayer renders off its own display link.
//

import ScreenSaver
import QuartzCore

private let logger = AppexLog.logger("View")

final class AppexSaverMinimalView: ScreenSaverView {

    private let animator = RainbowAnimator()
    private var video: VideoPlayerController?

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
        video?.stop()
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = NSColor.black.cgColor
        layer.isOpaque = true
        return layer
    }

    // MARK: - ScreenSaverView overrides (kept so the framework can drive them)

    override func startAnimation() {
        super.startAnimation()
        renderIfPossible()
    }

    override func stopAnimation() {
        video?.stop()
        animator.stop()
        super.stopAnimation()
    }

    // MARK: - View lifecycle (primary driver)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            renderIfPossible()
        } else {
            video?.stop()
            animator.stop()
        }
    }

    override func layout() {
        super.layout()
        video?.updateBounds(bounds)
        animator.updateBounds(bounds)
    }

    // MARK: - Rendering

    private func renderIfPossible() {
        guard window != nil, let layer = self.layer else { return }

        let cached = VideoCache.videos()
        if !cached.isEmpty {
            animator.stop()
            if video == nil {
                let controller = VideoPlayerController(videos: cached)
                controller.attach(to: layer)
                controller.updateBounds(bounds)
                video = controller
            }
            logger.info("Playing \(cached.count, privacy: .public) cached video(s)")
            video?.start()
        } else {
            video?.stop()
            logger.info("No cached videos; using rainbow fallback")
            animator.attach(to: layer)
            animator.updateBounds(bounds)
            animator.start()
        }
    }
}
