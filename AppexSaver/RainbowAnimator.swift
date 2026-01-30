//
//  RainbowAnimator.swift
//  AppexSaver
//
//  Shared animation logic for rainbow color cycling with version text overlay.
//  Used by both the screensaver extension and host app preview.
//

import QuartzCore
import AppKit

/// Animates a rainbow color cycle on a CALayer with rotating version text overlay.
final class RainbowAnimator {

    // MARK: - Properties

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

    /// Frame counter
    private(set) var frameCount: Int = 0

    /// Current color index in rainbow array
    private var currentColorIndex: Int = 0

    /// Progress through current color phase (0-0.5 = hold, 0.5-1.0 = transition)
    private var colorPhaseProgress: CGFloat = 0.0

    /// Current corner for text overlay
    private var currentCorner: Corner = .topLeft

    /// Number of frames per full color phase (5 seconds at 60 FPS)
    private let framesPerColorPhase: Int = 300

    /// Animation timer
    private var animationTimer: Timer?

    /// The layer being animated
    private weak var parentLayer: CALayer?

    /// Text layer for version overlay
    private var textLayer: CATextLayer?

    /// Current bounds for text positioning
    private var bounds: CGRect = .zero

    // MARK: - Public API

    /// Attach animator to a layer
    func attach(to layer: CALayer) {
        parentLayer = layer
        layer.backgroundColor = rainbowColors[0].cgColor
        layer.isOpaque = true
        setupTextLayer()
    }

    /// Start the animation
    func start() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// Stop the animation
    func stop() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    /// Update bounds for text positioning
    func updateBounds(_ newBounds: CGRect) {
        bounds = newBounds
        updateTextLayerPosition()
    }

    /// Current background color based on animation phase
    var currentBackgroundColor: NSColor {
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

    // MARK: - Animation Logic

    /// Animation tick - called by timer
    private func tick() {
        frameCount += 1

        // Advance color animation
        colorPhaseProgress += 1.0 / CGFloat(framesPerColorPhase)

        // When phase completes, advance to next color and rotate corner
        if colorPhaseProgress >= 1.0 {
            colorPhaseProgress = 0.0
            currentColorIndex = (currentColorIndex + 1) % rainbowColors.count

            // Rotate to next corner
            let nextCornerRawValue = (currentCorner.rawValue + 1) % Corner.allCases.count
            currentCorner = Corner(rawValue: nextCornerRawValue) ?? .topLeft

            // Update text layer position
            updateTextLayerPosition()
        }

        // Update layer background color directly
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        parentLayer?.backgroundColor = currentBackgroundColor.cgColor
        CATransaction.commit()
    }

    // MARK: - Color Interpolation

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

    // MARK: - Text Layer

    private func setupTextLayer() {
        guard textLayer == nil, let layer = parentLayer else { return }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        let newTextLayer = CATextLayer()
        newTextLayer.string = "AppexSaver v\(version) (\(build))"
        newTextLayer.fontSize = 24
        newTextLayer.font = NSFont.systemFont(ofSize: 24, weight: .medium)
        newTextLayer.foregroundColor = NSColor.white.cgColor
        newTextLayer.shadowColor = NSColor.black.cgColor
        newTextLayer.shadowOffset = CGSize(width: 2, height: -2)
        newTextLayer.shadowRadius = 3
        newTextLayer.shadowOpacity = 0.8
        newTextLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        layer.addSublayer(newTextLayer)
        textLayer = newTextLayer

        updateTextLayerPosition()
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
}
