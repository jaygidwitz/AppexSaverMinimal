//
//  MenuBarAgent.swift
//  Surrealism · Ambient
//
//  The menu-bar presence that owns the wallpaper's quick controls (U4). Installed
//  on first "Set as wallpaper" so the wallpaper survives the main window closing;
//  removed when wallpaper stops. Commands route through the shared PlaybackCommands
//  (fanning out across every display). The dock icon is retained (KTD4).
//

import AppKit

/// Pure app-lifecycle decisions, unit-tested independently of the delegate.
enum AmbientLifecycle {
    /// A SwiftUI `WindowGroup` app quits on last-window-close unless the delegate
    /// says otherwise — keep the process (and wallpaper) alive while it's active.
    static func shouldTerminateAfterLastWindowClosed(wallpaperActive: Bool) -> Bool {
        !wallpaperActive
    }
}

@MainActor
final class MenuBarAgent: NSObject {
    private var statusItem: NSStatusItem?
    private let commands: PlaybackCommands
    private let onStopWallpaper: () -> Void
    private let onOpen: () -> Void
    private let onQuit: () -> Void

    init(commands: PlaybackCommands,
         onStopWallpaper: @escaping () -> Void,
         onOpen: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.commands = commands
        self.onStopWallpaper = onStopWallpaper
        self.onOpen = onOpen
        self.onQuit = onQuit
        super.init()
    }

    var isInstalled: Bool { statusItem != nil }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack",
                                     accessibilityDescription: "Surrealism wallpaper")
        item.menu = buildMenu()
        statusItem = item
    }

    func remove() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add("Play / Pause", #selector(playPause))
        add("Next Loop", #selector(next))
        menu.addItem(.separator())
        add("Stop Wallpaper", #selector(stopWallpaper))
        add("Open Surrealism", #selector(open))
        menu.addItem(.separator())
        add("Quit Surrealism", #selector(quit))
        return menu
    }

    @objc private func playPause() { commands.playPause() }
    @objc private func next() { commands.next() }
    @objc private func stopWallpaper() { onStopWallpaper() }
    @objc private func open() { onOpen() }
    @objc private func quit() { onQuit() }
}
