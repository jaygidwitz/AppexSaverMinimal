//
//  FullScreenPlayer.swift
//  Surrealism · Commerce
//
//  Plays a loop — or a rotation of loops — full-screen. A borderless overlay
//  fades in over the current Space (no full-screen Space-slide, no black flash).
//  Cursor auto-hides after a moment of stillness. Esc / click exits.
//
//  Backed by VideoPlayerController (the same two-layer cross-fade engine the
//  screensaver uses) so the in-app player fades between clips and honors the
//  shared playback settings — shuffle, cross-fade, and rotation (U4).
//

import AppKit
import AVFoundation

@MainActor
enum FullScreenPlayer {
    private static var window: OverlayWindow?
    private static var controller: VideoPlayerController?
    private static var propagator: PlaybackPropagator?
    private static var cursorTimer: Timer?

    /// The controller currently on screen, so live settings changes (U6) can drive it.
    static var activeController: VideoPlayerController? { controller }

    /// Play a single loop, seamlessly repeated.
    static func play(url: URL, title: String) {
        present(videos: [url], shuffle: false, crossFade: PlaybackSettings.defaultFade)
    }

    /// Play a rotation of loops with cross-fades, optionally shuffled. When
    /// `liveSettings` is provided, changes to it apply to the running player (U6).
    static func playPlaylist(urls: [URL], title: String,
                             shuffle: Bool = true,
                             crossFade: TimeInterval = PlaybackSettings.defaultFade,
                             liveSettings: PlaybackSettings? = nil,
                             library: (() -> [URL])? = nil) {
        guard !urls.isEmpty else { return }
        present(videos: urls, shuffle: shuffle, crossFade: crossFade,
                liveSettings: liveSettings, library: library)
    }

    // MARK: - Presentation

    private static func present(videos: [URL], shuffle: Bool, crossFade: TimeInterval,
                                liveSettings: PlaybackSettings? = nil,
                                library: (() -> [URL])? = nil) {
        close(animated: false)

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let vpc = VideoPlayerController(videos: videos, shuffle: shuffle)
        vpc.setFadeDuration(crossFade)
        vpc.setVideoGravity(.resizeAspect)   // letterbox — keep the whole frame visible
        vpc.attach(to: container.layer!)
        vpc.updateBounds(container.bounds)
        controller = vpc

        // Live-drive the running player from the shared settings (U6).
        if let liveSettings {
            propagator = PlaybackPropagator(settings: liveSettings, engine: vpc,
                                            library: library ?? { videos })
        }

        let win = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = container
        win.isOpaque = true
        win.backgroundColor = .black
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.acceptsMouseMovedEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.onExit = { close() }
        win.onMouseMoved = { cursorActivity() }

        NSApp.presentationOptions = [.hideDock, .autoHideMenuBar]

        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        vpc.start()
        cursorActivity()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1
        }
        window = win
    }

    /// Called on show + every mouse move: keep the cursor visible and re-arm the
    /// idle timer that hides it after a couple seconds of stillness.
    private static func cursorActivity() {
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    static func close(animated: Bool = true) {
        cursorTimer?.invalidate(); cursorTimer = nil
        NSCursor.setHiddenUntilMouseMoves(false)
        guard let win = window else { return }
        window = nil
        let teardown: () -> Void = {
            propagator = nil
            controller?.stop()
            controller = nil
            win.orderOut(nil)
            NSApp.presentationOptions = []
        }
        guard animated else { teardown(); return }
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.2; win.animator().alphaValue = 0 },
                                             completionHandler: teardown)
    }
}

/// Borderless window that takes key input (Esc / click to dismiss) and reports
/// mouse movement (so the cursor can auto-hide).
private final class OverlayWindow: NSWindow {
    var onExit: (() -> Void)?
    var onMouseMoved: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?() } else { super.keyDown(with: event) }   // Esc
    }
    override func mouseDown(with event: NSEvent) { onExit?() }
    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
}
