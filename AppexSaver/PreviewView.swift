//
//  PreviewView.swift
//  AppexSaver
//
//  NSView subclass that hosts the rainbow animation for preview in the host app.
//

import AppKit
import WebKit

/// A view that displays the screensaver animation for preview purposes.
final class PreviewView: NSView {

    private let animator = RainbowAnimator()
    private var webView: WKWebView?

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

        let wv = WKWebView(frame: leftHalfFrame())
        wv.autoresizingMask = [.height]
        addSubview(wv)
        wv.loadHTMLString("<h1>Hello from WKWebView</h1>", baseURL: nil)
        webView = wv
    }

    private func leftHalfFrame() -> NSRect {
        NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
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
        webView?.frame = leftHalfFrame()
    }

    deinit {
        animator.stop()
    }
}
