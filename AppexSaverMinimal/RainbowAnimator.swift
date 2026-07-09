//
//  RainbowAnimator.swift
//  AppexSaverMinimal
//
//  Copyright © 2026. Licensed under the MIT License.
//
//  Brand fallback backdrop shown when the video cache is empty — and, crucially,
//  what the macOS Screen Saver picker captures as the small preview thumbnail.
//  Repurposed from the template's Apple-rainbow fallback into a dark iridescent
//  "oil-slick" gradient (the brand's --iris), with the old debug version label
//  removed. Name kept for compatibility with both targets' membership.
//
//  Shared between AppexSaverMinimalView (the appex) and PreviewView (the host).
//

import AppKit
import QuartzCore

final class RainbowAnimator {

    /// Iridescent hues (magenta → violet → indigo → cyan → gold), matching the
    /// brand wordmark's gradient.
    private let iris: [CGColor] = [
        NSColor(red: 0.91, green: 0.47, blue: 0.98, alpha: 1).cgColor, // magenta
        NSColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1).cgColor, // violet
        NSColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1).cgColor, // indigo
        NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1).cgColor, // cyan
        NSColor(red: 0.96, green: 0.79, blue: 0.49, alpha: 1).cgColor, // gold
    ]

    private weak var parentLayer: CALayer?
    private var gradient: CAGradientLayer?

    /// Deep violet-black initial backing color for `makeBackingLayer()`.
    var currentBackgroundColor: NSColor { NSColor(red: 0.03, green: 0.02, blue: 0.06, alpha: 1) }

    func attach(to layer: CALayer) {
        parentLayer = layer
        layer.backgroundColor = currentBackgroundColor.cgColor
        layer.isOpaque = true

        let g = gradient ?? CAGradientLayer()
        g.colors = iris
        g.locations = [0, 0.28, 0.52, 0.76, 1]
        g.startPoint = CGPoint(x: 0.03, y: 0.0)
        g.endPoint = CGPoint(x: 0.97, y: 1.0)
        g.frame = layer.bounds
        if g.superlayer == nil { layer.addSublayer(g) }
        gradient = g
    }

    func start() {
        // Gentle endless drift so the fullscreen fallback feels alive; harmless
        // for the (static) picker thumbnail.
        guard let g = gradient, g.animation(forKey: "drift") == nil else { return }
        let a = CABasicAnimation(keyPath: "startPoint")
        a.fromValue = CGPoint(x: 0.03, y: 0.0)
        a.toValue = CGPoint(x: 0.30, y: 0.18)
        a.duration = 14
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        g.add(a, forKey: "drift")
    }

    func stop() {
        gradient?.removeAnimation(forKey: "drift")
    }

    func updateBounds(_ bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient?.frame = bounds
        CATransaction.commit()
    }
}
