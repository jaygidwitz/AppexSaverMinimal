//
//  FullScreenPlayer.swift
//  Surrealism · Commerce
//
//  Plays a loop — or the whole library as a playlist — full-screen. A borderless
//  overlay fades in over the current Space (no full-screen Space-slide, no black
//  flash). Cursor auto-hides after a moment of stillness. Esc / click exits.
//

import AppKit
import AVKit
import AVFoundation

@MainActor
enum FullScreenPlayer {
    private static var window: OverlayWindow?
    private static var player: AVQueuePlayer?
    private static var looper: AVPlayerLooper?
    private static var endObserver: NSObjectProtocol?
    private static var cursorTimer: Timer?

    /// Play a single loop, seamlessly repeated.
    static func play(url: URL, title: String) {
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        looper = AVPlayerLooper(player: queue, templateItem: item)
        present(queue: queue, title: title)
    }

    /// Play the whole library as a looping, shuffled playlist.
    static func playPlaylist(urls: [URL], title: String) {
        guard !urls.isEmpty else { return }
        let ordered = urls.shuffled()
        let queue = AVQueuePlayer(items: ordered.map { AVPlayerItem(url: $0) })
        // As each loop finishes, re-queue it at the end so the library cycles forever.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { note in
            guard let item = note.object as? AVPlayerItem,
                  let asset = item.asset as? AVURLAsset else { return }
            queue.insert(AVPlayerItem(url: asset.url), after: nil)
        }
        present(queue: queue, title: title)
    }

    // MARK: - Presentation

    private static func present(queue: AVQueuePlayer, title: String) {
        close(animated: false)
        queue.isMuted = true
        player = queue

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let playerView = AVPlayerView()
        playerView.player = queue
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect

        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        playerView.frame = container.bounds
        playerView.autoresizingMask = [.width, .height]
        container.addSubview(playerView)

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
        queue.play()
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
            player?.pause()
            if let obs = endObserver { NotificationCenter.default.removeObserver(obs); endObserver = nil }
            player = nil
            looper = nil
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
