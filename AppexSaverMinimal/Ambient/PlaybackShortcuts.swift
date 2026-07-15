//
//  PlaybackShortcuts.swift
//  Surrealism · Ambient
//
//  Two discoverability channels over PlaybackCommands (U1):
//   • bare-key handling inside a presenting surface (Space / → / N / [ / ] / F),
//     called from the surface window's keyDown (PlaybackShortcuts);
//   • the macOS main-menu "Playback" group (PlaybackMenuCommands, mounted via
//     CommandMenu in AppexSaverMinimalApp) whose items carry ⌘ key-equivalents so
//     the shortcuts are self-documenting, and which grey out when no surface is
//     active.
//
//  The bare in-surface keys and the ⌘ menu items intentionally coexist: bare keys
//  are the fast path while watching; the ⌘ menu is the always-present, app-wide
//  discoverable reference (bare menu equivalents would hijack keys in the main
//  window, so the menu uses ⌘).
//

import AppKit
import SwiftUI

@MainActor
final class PlaybackShortcuts: NSObject {
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

}

/// The main-menu "Playback" group (U1), mounted with `CommandMenu` in the app
/// scene. Items route to whichever surface is presenting (Theater first, then
/// wallpaper) and grey out when neither is. The trailing hint line documents
/// the bare keys that work *inside* a surface.
struct PlaybackMenuCommands: View {
    @ObservedObject var ambient: AmbientState
    /// Resolved per invocation — the active surface's live command set.
    let commands: () -> PlaybackCommands?

    private var active: Bool { ambient.theaterActive || ambient.wallpaperActive }

    var body: some View {
        Button("Play / Pause") { commands()?.playPause() }
            .keyboardShortcut(.space, modifiers: [.option])
            .disabled(!active)
        Button("Next Loop") { commands()?.next() }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!active)
        Divider()
        Button("Cross-fade Longer") { commands()?.crossFadeStep(+1) }
            .keyboardShortcut("]", modifiers: [.command])
            .disabled(!active)
        Button("Cross-fade Shorter") { commands()?.crossFadeStep(-1) }
            .keyboardShortcut("[", modifiers: [.command])
            .disabled(!active)
        Divider()
        Button("Toggle Fullscreen") { commands()?.togglePresentation() }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(!ambient.theaterActive)
        Divider()
        // Disabled reference line: the bare keys available while watching.
        Text("In Theater: Space · → · [ ] · F · Esc")
    }
}
