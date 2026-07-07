//
//  FullScreenPlayer.swift
//  Surrealism · Commerce
//
//  Plays a downloaded loop in a full-screen, looping AVPlayer window. Opened by
//  clicking a loop that's in the library. Esc / ⌘W closes it.
//

import AppKit
import AVKit
import AVFoundation

@MainActor
enum FullScreenPlayer {
    private static var window: NSWindow?
    private static var loopObserver: NSObjectProtocol?

    static func play(url: URL, title: String) {
        close() // one player window at a time

        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        player.isMuted = true
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }

        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect

        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let win = NSWindow(contentRect: frame,
                           styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Surrealism — \(title)"
        win.contentView = playerView
        win.isReleasedWhenClosed = false
        win.backgroundColor = .black
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.collectionBehavior = [.fullScreenPrimary]
        win.toggleFullScreen(nil)
        player.play()

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { _ in
            player.pause()
            close()
        }
        window = win
    }

    static func close() {
        if let obs = loopObserver { NotificationCenter.default.removeObserver(obs); loopObserver = nil }
        window = nil
    }
}
