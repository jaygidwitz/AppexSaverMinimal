//
//  TheaterControlsOverlay.swift
//  Surrealism · Ambient
//
//  The auto-hiding transport overlay for the Theater (U2). One clean control bar
//  bound to the shared PlaybackCommands / PlaybackSettings — the on-screen,
//  clickable half of the four discoverability channels (KTD2). Revealed by the
//  Theater window on mouse-move / key / VoiceOver focus, hidden on idle.
//

import SwiftUI

struct TheaterControlsOverlay: View {
    @ObservedObject var settings: PlaybackSettings
    let commands: PlaybackCommands
    /// Live-updated by the Theater window to trigger a fade in/out.
    var visible: Bool

    @State private var isPlaying = true
    private let accent = Color(red: 0.55, green: 0.4, blue: 0.95)

    var body: some View {
        HStack(spacing: 18) {
            control(isPlaying ? "pause.fill" : "play.fill", "Play or pause (Space)") {
                commands.playPause(); isPlaying = commands.isPlaying
            }
            control("forward.end.fill", "Next loop (→)") { commands.next() }

            Divider().frame(height: 22).overlay(Color.white.opacity(0.15))

            Toggle("", isOn: Binding(get: { settings.shuffle },
                                     set: { _ in commands.toggleShuffle() }))
                .toggleStyle(.switch).tint(accent).labelsHidden()
                .help("Shuffle (S)")
            Label("Shuffle", systemImage: "shuffle").labelStyle(.iconOnly)
                .foregroundStyle(settings.shuffle ? accent : .white.opacity(0.6))

            Divider().frame(height: 22).overlay(Color.white.opacity(0.15))

            control("minus", "Shorter cross-fade ([)") { commands.crossFadeStep(-1) }
            Text(String(format: "%.1fs", settings.crossFadeSeconds))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 34)
            control("plus", "Longer cross-fade (])") { commands.crossFadeStep(+1) }

            Divider().frame(height: 22).overlay(Color.white.opacity(0.15))

            control("rectangle.inset.filled", "Fullscreen / windowed (F)") { commands.togglePresentation() }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.22), value: visible)
        .onAppear { isPlaying = commands.isPlaying }
    }

    @ViewBuilder private func control(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white).frame(width: 30, height: 26)
        }
        .buttonStyle(.plain).help(help)
    }
}
