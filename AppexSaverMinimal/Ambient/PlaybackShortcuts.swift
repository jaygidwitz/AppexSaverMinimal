//
//  PlaybackShortcuts.swift
//  Surrealism · Ambient
//
//  Two discoverability channels over PlaybackCommands (U1):
//   • bare-key handling inside a presenting surface (Space / → / N / S / [ / ] / F),
//     called from the surface window's keyDown;
//   • a macOS main-menu "Playback" group whose items carry ⌘ key-equivalents so the
//     shortcuts are self-documenting, and which grey out when no surface is active.
//
//  The bare in-surface keys and the ⌘ menu items intentionally coexist: bare keys
//  are the fast path while watching; the ⌘ menu is the always-present, app-wide
//  discoverable reference (bare menu equivalents would hijack keys in the main
//  window, so the menu uses ⌘).
//

import AppKit

@MainActor
final class PlaybackShortcuts: NSObject, NSMenuItemValidation {
    private let commands: PlaybackCommands

    // macOS virtual key codes.
    private enum Key {
        static let space: UInt16 = 49
        static let rightArrow: UInt16 = 124
        static let n: UInt16 = 45
        static let s: UInt16 = 1
        static let leftBracket: UInt16 = 33
        static let rightBracket: UInt16 = 30
        static let f: UInt16 = 3
    }

    init(commands: PlaybackCommands) {
        self.commands = commands
        super.init()
    }

    /// Handle a bare-key transport shortcut from a presenting surface's keyDown.
    /// Returns true if the key was a transport command (and was consumed).
    /// Esc/exit is owned by the window, not here.
    func handle(_ event: NSEvent) -> Bool {
        // Only bare keys — let ⌘/⌥/⌃ combos fall through to the menu/responder chain.
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
        case Key.space:                    commands.playPause()
        case Key.rightArrow, Key.n:        commands.next()
        case Key.leftBracket:              commands.crossFadeStep(-1)
        case Key.rightBracket:             commands.crossFadeStep(+1)
        case Key.f:                        commands.togglePresentation()
        default:                           return false
        }
        return true
    }

    /// Build the main-menu "Playback" group. Items are self-documenting (⌘ key
    /// equivalents) and validated against `hasActiveSurface`.
    func makeMenu(title: String = "Playback") -> NSMenu {
        let menu = NSMenu(title: title)
        func add(_ label: String, _ key: String, _ action: Selector) {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        add("Play / Pause", " ", #selector(playPauseAction))
        add("Next Loop", "n", #selector(nextAction))
        menu.addItem(.separator())
        add("Cross-fade Longer", "]", #selector(crossFadeUpAction))
        add("Cross-fade Shorter", "[", #selector(crossFadeDownAction))
        menu.addItem(.separator())
        add("Toggle Fullscreen", "f", #selector(togglePresentationAction))
        return menu
    }

    // Greys out every Playback item when no surface is presenting.
    func validateMenuItem(_ item: NSMenuItem) -> Bool { commands.hasActiveSurface }

    @objc private func playPauseAction() { commands.playPause() }
    @objc private func nextAction() { commands.next() }
    @objc private func shuffleAction() { commands.toggleShuffle() }
    @objc private func crossFadeUpAction() { commands.crossFadeStep(+1) }
    @objc private func crossFadeDownAction() { commands.crossFadeStep(-1) }
    @objc private func togglePresentationAction() { commands.togglePresentation() }
}
