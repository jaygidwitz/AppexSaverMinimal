//
//  TheaterWindow.swift
//  Surrealism · Ambient
//
//  The Theater surface (U2): an on-demand player to watch the rotation fullscreen
//  or windowed, with the shared transport overlay, keyboard/VoiceOver control, and
//  a one-time key hint. Built additively on the same VideoPlayerController +
//  PlaybackPropagator pattern as FullScreenPlayer — FullScreenPlayer itself is left
//  untouched, so the shipped "Play all" / tile-click paths cannot regress (R18).
//

import AppKit
import AVFoundation
import SwiftUI

/// Fullscreen ⇄ windowed presentation state — pure, so the toggle is testable.
enum TheaterPresentation: Equatable {
    case fullscreen, windowed
    var toggled: TheaterPresentation { self == .fullscreen ? .windowed : .fullscreen }
}

/// First-run key-hint gate — pure UserDefaults logic, unit-tested.
enum TheaterHint {
    static let key = "app.surrealism.theater.hintShown"
    static func shouldShow(_ defaults: UserDefaults) -> Bool { !defaults.bool(forKey: key) }
    static func markShown(_ defaults: UserDefaults) { defaults.set(true, forKey: key) }
}

@MainActor
enum TheaterWindow {
    private static var window: TheaterKeyWindow?
    private static var container: NSView?
    private static var controller: VideoPlayerController?
    private static var propagator: PlaybackPropagator?
    private static var commands: PlaybackCommands?
    private static var shortcuts: PlaybackShortcuts?
    private static var overlayHost: NSHostingView<TheaterControlsOverlay>?
    private static var hintHost: NSView?
    private static var idleTimer: Timer?
    private static var presentation: TheaterPresentation = .fullscreen
    private static var settings: PlaybackSettings?
    private static let windowedSize = NSSize(width: 1280, height: 720)

    /// Open the Theater on the current rotation, live-driven by `settings`.
    static func present(urls: [URL], settings: PlaybackSettings, library: @escaping () -> [URL]) {
        guard !urls.isEmpty else { return }
        close(animated: false)
        self.settings = settings

        // Start at the main screen's size so the video layers have real bounds
        // before the window sizes the view; `layout()` keeps them in sync on
        // windowed resize (else the AVPlayerLayers stay zero-sized → black).
        let startFrame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let box = TheaterContentView(frame: startFrame)
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.cgColor
        container = box

        let vpc = VideoPlayerController(videos: urls, shuffle: settings.shuffle)
        vpc.setFadeDuration(settings.crossFadeSeconds)
        vpc.setVideoGravity(.resizeAspect)
        vpc.attach(to: box.layer!)
        vpc.updateBounds(box.bounds)
        box.controller = vpc
        controller = vpc
        propagator = PlaybackPropagator(settings: settings, engine: vpc, library: library)

        let cmd = PlaybackCommands(settings: settings, controllers: { controller.map { [$0] } ?? [] })
        cmd.onTogglePresentation = { togglePresentation() }
        cmd.onStop = { close() }
        commands = cmd
        shortcuts = PlaybackShortcuts(commands: cmd)

        let overlay = NSHostingView(rootView: makeOverlay(visible: false))
        overlay.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            overlay.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -44),
        ])
        overlayHost = overlay

        present(in: .fullscreen)
        vpc.start()
        showActivity()
        showHintIfNeeded()
    }

    private static func makeOverlay(visible: Bool) -> TheaterControlsOverlay {
        TheaterControlsOverlay(settings: settings!, commands: commands!, visible: visible)
    }

    // MARK: Presentation

    static func togglePresentation() { present(in: presentation.toggled) }

    private static func present(in mode: TheaterPresentation) {
        guard let box = container else { return }
        presentation = mode
        let old = window

        let win: TheaterKeyWindow
        switch mode {
        case .fullscreen:
            let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            win = TheaterKeyWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.setFrame(frame, display: true)
            win.level = .floating
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            NSApp.presentationOptions = [.hideDock, .autoHideMenuBar]
        case .windowed:
            let frame = NSRect(origin: .zero, size: windowedSize)
            win = TheaterKeyWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                   backing: .buffered, defer: false)
            win.title = "Surrealism — Theater"
            win.center()
            NSApp.presentationOptions = []
        }
        win.isReleasedWhenClosed = false
        win.acceptsMouseMovedEvents = true
        win.backgroundColor = .black
        win.contentView = box               // re-parents the video + overlay, no restart
        win.onKey = { handleKey($0) }
        win.onMouseMoved = { showActivity() }
        win.onClose = { close() }
        win.makeKeyAndOrderFront(nil)
        window = win
        old?.orderOut(nil)
        showActivity()
    }

    // MARK: Activity (auto-hide overlay + cursor)

    private static func showActivity() {
        overlayHost?.rootView = makeOverlay(visible: true)
        NSCursor.setHiddenUntilMouseMoves(false)
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
            Task { @MainActor in
                overlayHost?.rootView = makeOverlay(visible: false)
                if presentation == .fullscreen { NSCursor.setHiddenUntilMouseMoves(true) }
            }
        }
    }

    // MARK: First-run key hint

    private static func showHintIfNeeded(defaults: UserDefaults = .standard) {
        guard let box = container, TheaterHint.shouldShow(defaults) else { return }
        TheaterHint.markShown(defaults)
        let hint = NSHostingView(rootView: TheaterHintView())
        hint.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            hint.topAnchor.constraint(equalTo: box.topAnchor, constant: 48),
        ])
        hintHost = hint
        // Auto-fade after a few seconds; never consumes a command/exit gesture.
        Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { _ in
            Task { @MainActor in
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.5; hint.animator().alphaValue = 0 },
                                                     completionHandler: { hintHost?.removeFromSuperview(); hintHost = nil })
            }
        }
    }

    // MARK: Key routing

    private static func handleKey(_ event: NSEvent) {
        showActivity()
        if shortcuts?.handle(event) == true { return }
        if event.keyCode == 53 { close() }            // Esc
    }

    // MARK: Teardown

    static func close(animated: Bool = true) {
        idleTimer?.invalidate(); idleTimer = nil
        NSCursor.setHiddenUntilMouseMoves(false)
        NSApp.presentationOptions = []
        hintHost?.removeFromSuperview(); hintHost = nil
        propagator = nil
        controller?.stop(); controller = nil
        commands = nil; shortcuts = nil
        overlayHost = nil; container = nil; settings = nil
        window?.orderOut(nil); window = nil
    }
}

/// Container that keeps the video layers filling its bounds across fullscreen ⇄
/// windowed resizes (the AVPlayerLayers are manually-added sublayers, so they need
/// their bounds pushed on every layout — otherwise they render black).
private final class TheaterContentView: NSView {
    weak var controller: VideoPlayerController?
    override func layout() {
        super.layout()
        controller?.updateBounds(bounds)
    }
}

/// Key/mouse-reporting window used for both fullscreen (borderless) and windowed
/// Theater presentations. Esc + transport keys route through `onKey`.
private final class TheaterKeyWindow: NSWindow {
    var onKey: ((NSEvent) -> Void)?
    var onMouseMoved: (() -> Void)?
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
    override func close() { onClose?(); super.close() }
}

/// The one-time key legend shown on first Theater open.
private struct TheaterHintView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Space play/pause · → next · [ ] cross-fade · F windowed · Esc exit")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}
