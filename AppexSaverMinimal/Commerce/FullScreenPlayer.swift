//
//  FullScreenPlayer.swift
//  Surrealism · Commerce
//
//  Plays a loop full-screen. Uses a borderless overlay window that fades in over
//  the current Space (no native full-screen Space-slide, no black flash) and
//  fades out on Esc / click. Video is looped and muted.
//

import AppKit
import AVKit
import AVFoundation

@MainActor
enum FullScreenPlayer {
    private static var window: OverlayWindow?
    private static var loopObserver: NSObjectProtocol?
    private static var player: AVQueuePlayer?
    private static var looper: AVPlayerLooper?

    static func play(url: URL, title: String) {
        close(animated: false)

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Player, muted + seamless loop via AVPlayerLooper.
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue

        let playerView = AVPlayerView()
        playerView.player = queue
        playerView.controlsStyle = .none          // immersive; Esc/click exits
        playerView.videoGravity = .resizeAspect

        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        playerView.frame = container.bounds
        playerView.autoresizingMask = [.width, .height]
        container.addSubview(playerView)

        let win = OverlayWindow(contentRect: frame, styleMask: .borderless,
                                backing: .buffered, defer: false)
        win.contentView = container
        win.isOpaque = true
        win.backgroundColor = .black
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.onExit = { close() }

        // Immersion: hide dock + menu bar while playing.
        NSApp.presentationOptions = [.hideDock, .autoHideMenuBar]

        // Fade in place — no Space transition.
        win.alphaValue = 0
        win.makeKeyAndOrderFront(nil)
        queue.play()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1
        }
        window = win
        _ = title
    }

    static func close(animated: Bool = true) {
        guard let win = window else { return }
        window = nil
        let teardown: () -> Void = {
            player?.pause()
            if let obs = loopObserver { NotificationCenter.default.removeObserver(obs); loopObserver = nil }
            player = nil
            looper = nil
            win.orderOut(nil)
            NSApp.presentationOptions = []
        }
        guard animated else { teardown(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            win.animator().alphaValue = 0
        }, completionHandler: teardown)
    }
}

/// Borderless window that can take key input so Esc / click can dismiss it.
private final class OverlayWindow: NSWindow {
    var onExit: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?() }        // Esc
        else { super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) { onExit?() }
}
