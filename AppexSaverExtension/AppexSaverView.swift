//
//  AppexSaverView.swift
//  AppexSaverExtension
//
//  ScreenSaverView that uses RainbowAnimator for the animation logic.
//

import ScreenSaver
import QuartzCore
import WebKit
import os.log

private let logger = Logger(subsystem: "com.glouel.screensaver.AppexSaver", category: "View")

/// Screensaver view that displays rainbow color animation with version overlay.
final class AppexSaverView: ScreenSaverView {

    // MARK: - Properties

    /// Shared animation logic
    private let animator = RainbowAnimator()

    /// Web view covering the left half of the screen
    private var webView: WKWebView?

    /// Frame counter (exposed for ViewController to read in deinit)
    var frameCount: Int { animator.frameCount }

    /// Preferred FPS - Arabesque has this property
    @objc var preferredFPS: Int { return 60 }

    // MARK: - Initialization

    override init?(frame: NSRect, isPreview: Bool) {
        logger.info("AppexSaverView.init(frame: \(frame.size.width, privacy: .public)x\(frame.size.height, privacy: .public), isPreview: \(isPreview))")
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        logger.info("AppexSaverView.init(coder:)")
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        animator.stop()
        logger.info("AppexSaverView.deinit - frameCount: \(self.animator.frameCount)")
    }

    private func commonInit() {
        // Enable layer-backed view
        self.wantsLayer = true

        // Set animation time interval (60 FPS)
        animationTimeInterval = 1.0 / 60.0

        // Add WKWebView covering the left half
        let wv = WKWebView(frame: leftHalfFrame())
        wv.autoresizingMask = [.height]
        addSubview(wv)
        wv.loadHTMLString("<h1>Hello from WKWebView</h1>", baseURL: nil)
        webView = wv

        logger.info("commonInit() completed")
    }

    private func leftHalfFrame() -> NSRect {
        NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
    }

    // MARK: - Layer Setup (Arabesque implements this)

    override func makeBackingLayer() -> CALayer {
        logger.info("makeBackingLayer()")
        let layer = CALayer()
        layer.backgroundColor = animator.currentBackgroundColor.cgColor
        layer.isOpaque = true
        return layer
    }

    // MARK: - ScreenSaverView Overrides

    override func startAnimation() {
        logger.info("startAnimation() - isAnimating before: \(self.isAnimating)")
        super.startAnimation()
        animator.start()
        logger.info("startAnimation() - isAnimating after: \(self.isAnimating)")
    }

    override func stopAnimation() {
        logger.info("stopAnimation() - frameCount: \(self.animator.frameCount)")
        animator.stop()
        super.stopAnimation()
    }

    override func animateOneFrame() {
        // Log first call to confirm if framework ever calls this
        if animator.frameCount == 0 {
            logger.info("animateOneFrame() - FIRST CALL from framework")
        }
        // Framework may or may not call this - timer in animator handles animation reliably
    }

    // MARK: - View Lifecycle

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        let superviewType = self.superview.map { String(describing: type(of: $0)) } ?? "nil"
        logger.info("viewDidMoveToSuperview() - superview: \(superviewType, privacy: .public)")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        logger.info("viewDidMoveToWindow() - hasWindow: \(self.window != nil)")

        if self.window != nil {
            // Attach animator to our layer
            if let layer = self.layer {
                animator.attach(to: layer)
                animator.updateBounds(bounds)
            }

            // Start animation when we have a window
            animator.start()
        } else {
            // Stop animation when removed from window
            animator.stop()
        }
    }

    override func layout() {
        super.layout()
        animator.updateBounds(bounds)
        webView?.frame = leftHalfFrame()
    }
}
