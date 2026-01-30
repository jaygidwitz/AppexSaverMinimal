//
//  PreviewView.swift
//  AppexSaver
//
//  NSView subclass that hosts the rainbow animation for preview in the host app.
//

import AppKit

/// A view that displays the screensaver animation for preview purposes.
final class PreviewView: NSView {

    private let animator = RainbowAnimator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
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
