//
//  AppexSaverView.swift
//  AppexSaverExtension
//
//  Simplified ScreenSaverView matching Apple's Arabesque.appex pattern.
//  Just displays a solid color background.
//
//  Apple's pattern:
//  - makeBackingLayer()
//  - preferredFPS property
//  - No auto-start animation in viewDidMoveToWindow()
//

import ScreenSaver
import QuartzCore
import os.log

private let logger = Logger(subsystem: "com.glouel.AppexSaver", category: "View")

/// Simplified screensaver view - just displays a solid background color.
final class AppexSaverView: ScreenSaverView {

    // MARK: - Properties

    /// Frame counter for logging (exposed for ViewController to read in deinit)
    private(set) var frameCount: Int = 0

    /// Rainbow colors array (7 colors)
    private let rainbowColors: [NSColor] = [
        NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),   // Red
        NSColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),   // Orange
        NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0),   // Yellow
        NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),   // Green
        NSColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0),   // Blue
        NSColor(red: 0.29, green: 0.0, blue: 0.51, alpha: 1.0), // Indigo
        NSColor(red: 0.56, green: 0.0, blue: 1.0, alpha: 1.0)   // Violet
    ]

    /// Corner positions for rotating text
    private enum Corner: Int, CaseIterable {
        case topLeft, topRight, bottomRight, bottomLeft
    }

    /// Current color index in rainbow array
    private var currentColorIndex: Int = 0

    /// Progress through current color phase (0-0.5 = hold, 0.5-1.0 = transition)
    private var colorPhaseProgress: CGFloat = 0.0

    /// Current corner for text overlay
    private var currentCorner: Corner = .topLeft

    /// Number of frames per full color phase (5 seconds at 60 FPS)
    private let framesPerColorPhase: Int = 300

    /// Custom animation timer (framework's animateOneFrame may not be called reliably)
    private var animationTimer: Timer?

    /// Text layer for version overlay (CATextLayer instead of draw())
    private var textLayer: CATextLayer?

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
        stopAnimationTimer()
        logger.info("AppexSaverView.deinit - frameCount: \(self.frameCount)")
    }

    private func commonInit() {
        // Enable layer-backed view
        self.wantsLayer = true

        // Set animation time interval (60 FPS)
        animationTimeInterval = 1.0 / 60.0

        logger.info("commonInit() completed")
    }

    // MARK: - Timer Management

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        logger.info("Animation timer started")
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        logger.info("Animation timer stopped")
    }

    /// Animation tick - called by timer and/or animateOneFrame
    private func tick() {
        frameCount += 1

        // Advance color animation
        colorPhaseProgress += 1.0 / CGFloat(framesPerColorPhase)

        // When phase completes, advance to next color and rotate corner
        if colorPhaseProgress >= 1.0 {
            logger.debug("tick() switching color")
            colorPhaseProgress = 0.0
            currentColorIndex = (currentColorIndex + 1) % rainbowColors.count

            // Rotate to next corner
            let nextCornerRawValue = (currentCorner.rawValue + 1) % Corner.allCases.count
            currentCorner = Corner(rawValue: nextCornerRawValue) ?? .topLeft

            // Update text layer position
            updateTextLayerPosition()
        }

        // Log every second (at 60fps)
        if frameCount == 1 || frameCount % 60 == 0 {
            let windowVisible = self.window?.isVisible ?? false
            let windowOnScreen = self.window?.isOnActiveSpace ?? false
            logger.debug("tick() frame \(self.frameCount), visible: \(windowVisible), onScreen: \(windowOnScreen)")
        }

        // Update layer background color directly (don't rely on draw())
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // Disable implicit animations
        self.layer?.backgroundColor = currentBackgroundColor.cgColor
        CATransaction.commit()
    }

    // MARK: - Color Animation Helpers

    /// Linear interpolation between two colors
    private func interpolateColor(from: NSColor, to: NSColor, progress: CGFloat) -> NSColor {
        let clampedProgress = max(0, min(1, progress))

        let fromRed = from.redComponent
        let fromGreen = from.greenComponent
        let fromBlue = from.blueComponent

        let toRed = to.redComponent
        let toGreen = to.greenComponent
        let toBlue = to.blueComponent

        return NSColor(
            red: fromRed + (toRed - fromRed) * clampedProgress,
            green: fromGreen + (toGreen - fromGreen) * clampedProgress,
            blue: fromBlue + (toBlue - fromBlue) * clampedProgress,
            alpha: 1.0
        )
    }

    /// Current background color based on animation phase
    private var currentBackgroundColor: NSColor {
        let currentColor = rainbowColors[currentColorIndex]

        // First half of phase: hold at current color
        if colorPhaseProgress < 0.5 {
            return currentColor
        }

        // Second half: transition to next color
        let nextIndex = (currentColorIndex + 1) % rainbowColors.count
        let nextColor = rainbowColors[nextIndex]
        let transitionProgress = (colorPhaseProgress - 0.5) * 2.0  // Map 0.5-1.0 to 0-1

        return interpolateColor(from: currentColor, to: nextColor, progress: transitionProgress)
    }

    // MARK: - Text Layer Setup

    private func setupTextLayer() {
        guard textLayer == nil, let parentLayer = self.layer else { return }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let layer = CATextLayer()
        layer.string = "AppexSaver v\(version)"
        layer.fontSize = 24
        layer.font = NSFont.systemFont(ofSize: 24, weight: .medium)
        layer.foregroundColor = NSColor.white.cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOffset = CGSize(width: 2, height: -2)
        layer.shadowRadius = 3
        layer.shadowOpacity = 0.8
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        parentLayer.addSublayer(layer)
        textLayer = layer

        updateTextLayerPosition()
        logger.info("setupTextLayer() completed")
    }

    private func updateTextLayerPosition() {
        guard let layer = textLayer else { return }

        // Calculate text size
        let text = layer.string as? String ?? ""
        let font = NSFont.systemFont(ofSize: 24, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = text.size(withAttributes: attributes)

        let padding: CGFloat = 20
        var position: CGPoint

        switch currentCorner {
        case .topLeft:
            position = CGPoint(x: padding, y: bounds.height - textSize.height - padding)
        case .topRight:
            position = CGPoint(x: bounds.width - textSize.width - padding, y: bounds.height - textSize.height - padding)
        case .bottomRight:
            position = CGPoint(x: bounds.width - textSize.width - padding, y: padding)
        case .bottomLeft:
            position = CGPoint(x: padding, y: padding)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = CGRect(x: position.x, y: position.y, width: textSize.width + 10, height: textSize.height + 5)
        CATransaction.commit()
    }

    // MARK: - Layer Setup (Arabesque implements this)

    override func makeBackingLayer() -> CALayer {
        logger.info("makeBackingLayer()")
        let layer = CALayer()
        layer.backgroundColor = rainbowColors[0].cgColor
        layer.isOpaque = true
        return layer
    }

    // MARK: - ScreenSaverView Overrides

    override func startAnimation() {
        logger.info("startAnimation() - isAnimating before: \(self.isAnimating)")
        super.startAnimation()
        startAnimationTimer()
        logger.info("startAnimation() - isAnimating after: \(self.isAnimating)")
    }

    override func stopAnimation() {
        logger.info("stopAnimation() - frameCount: \(self.frameCount)")
        stopAnimationTimer()
        super.stopAnimation()
    }

    override func animateOneFrame() {
        // Log first call to confirm if framework ever calls this
        if frameCount == 0 {
            logger.info("animateOneFrame() - FIRST CALL from framework")
        }
        // Framework may or may not call this - timer handles animation reliably
        tick()
    }

    // MARK: - View Lifecycle (minimal - no auto-start)

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        let superviewType = self.superview.map { String(describing: type(of: $0)) } ?? "nil"
        logger.info("viewDidMoveToSuperview() - superview: \(superviewType, privacy: .public)")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        logger.info("viewDidMoveToWindow() - hasWindow: \(self.window != nil)")

        if self.window != nil {
            // Set layer background color when we have a window
            if let layer = self.layer {
                layer.backgroundColor = currentBackgroundColor.cgColor
            }

            // Setup text layer for version overlay
            setupTextLayer()

            // Start timer here since framework may never call startAnimation()
            startAnimationTimer()
        } else {
            // Stop timer when removed from window
            stopAnimationTimer()
        }
    }
}
