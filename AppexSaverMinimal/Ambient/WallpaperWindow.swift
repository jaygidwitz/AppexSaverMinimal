//
//  WallpaperWindow.swift
//  Surrealism · Ambient
//
//  A borderless window pinned just below the desktop icons (Plash-style, U3): the
//  loops play *behind* the icons, clicks pass through to the desktop, and it rides
//  along on every Space. It is entirely our own window — we never read or write the
//  system wallpaper (R16), so it sidesteps the macOS-26 aerial-slot breakage.
//

import AppKit
import AVFoundation

@MainActor
final class WallpaperWindow: NSWindow {
    /// One below the desktop-icon layer → renders behind the icons.
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)

    private let content = WallpaperContentView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = Self.desktopLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true            // desktop clicks pass through
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        content.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView = content
        setFrame(screen.frame, display: false)
    }

    /// Attach a controller's video and keep it filling the window.
    func mount(_ controller: VideoPlayerController) {
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        controller.attach(to: content.layer!)
        controller.updateBounds(content.bounds)
        content.controller = controller
    }

    /// Reposition to a (possibly changed) screen frame.
    func reposition(to screen: NSScreen) { setFrame(screen.frame, display: true) }
}

/// Layer-hosting container that keeps the video layers filling its bounds across
/// resolution / arrangement changes (manually-added sublayers need bounds pushed).
private final class WallpaperContentView: NSView {
    weak var controller: VideoPlayerController?
    override func layout() {
        super.layout()
        controller?.updateBounds(bounds)
    }
}
