//
//  PreviewView.swift
//  AppexSaverMinimal
//
//  Copyright © 2026. Licensed under the MIT License.
//
//  NSView that runs the same VideoPlayerController the screensaver extension
//  uses, so the host app's preview matches what the screensaver displays.
//  Falls back to the RainbowAnimator when the cache is empty.
//

import AppKit

final class PreviewView: NSView {

    private let animator = RainbowAnimator()
    private var video: VideoPlayerController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = NSColor.black.cgColor
        layer.isOpaque = true
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { render() } else { stopAll() }
    }

    override func layout() {
        super.layout()
        video?.updateBounds(bounds)
        animator.updateBounds(bounds)
    }

    deinit { stopAll() }

    /// Rebuild playback from the current cache contents (call after add/remove).
    func reload() {
        stopAll()
        video = nil
        render()
    }

    private func render() {
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
            video?.start()
        } else {
            video?.stop()
            animator.attach(to: layer)
            animator.updateBounds(bounds)
            animator.start()
        }
    }

    private func stopAll() {
        video?.stop()
        animator.stop()
    }
}
