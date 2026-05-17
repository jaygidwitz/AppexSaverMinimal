//
//  PreviewView.swift
//  AppexSaverMinimal
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  NSView that runs the same RainbowAnimator the screensaver extension uses,
//  so the host app's Preview window matches what the screensaver displays.
//

import AppKit

final class PreviewView: NSView {

    private let animator = RainbowAnimator()

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
        layer.backgroundColor = animator.currentBackgroundColor.cgColor
        layer.isOpaque = true
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            if let layer = self.layer {
                animator.attach(to: layer)
                animator.updateBounds(bounds)
            }
            animator.start()
        } else {
            animator.stop()
        }
    }

    override func layout() {
        super.layout()
        animator.updateBounds(bounds)
    }

    deinit {
        animator.stop()
    }
}
