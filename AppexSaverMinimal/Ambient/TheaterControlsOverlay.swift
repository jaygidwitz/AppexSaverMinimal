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

    private var speedText: String {
        settings.playbackRate >= 0.999 ? "1×" : String(format: "%.2f×", settings.playbackRate)
    }

    var body: some View {
        HStack(spacing: 18) {
            control(isPlaying ? "pause.fill" : "play.fill", "Play or pause (Space)") {
                commands.playPause(); isPlaying = commands.isPlaying
            }
            control("forward.end.fill", "Next loop (→)") { commands.next() }

            Divider().frame(height: 22).overlay(Color.white.opacity(0.15))

            control("minus", "Shorter cross-fade ([)") { commands.crossFadeStep(-1) }
            Text(String(format: "%.1fs", settings.crossFadeSeconds))
                .font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(.white)
                .frame(width: 38)
            control("plus", "Longer cross-fade (])") { commands.crossFadeStep(+1) }

            Divider().frame(height: 22).overlay(Color.white.opacity(0.15))

            control("tortoise.fill", "Slower") {
                settings.setPlaybackRate(settings.playbackRate - 0.25)
            }
            Text(speedText)
                .font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(.white)
                .frame(width: 42)
            control("hare.fill", "Faster (up to normal speed)") {
                settings.setPlaybackRate(settings.playbackRate + 0.25)
            }

            Divider().frame(height: 22).overlay(Color.white.opacity(0.22))

            control("rectangle.inset.filled", "Fullscreen / windowed (F)") { commands.togglePresentation() }
        }
        .padding(.horizontal, 22).padding(.vertical, 13)
        // Dark frosted pill so white glyphs stay readable over bright video.
        .background(
            Capsule().fill(.black.opacity(0.58))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 18, y: 5)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.22), value: visible)
        .onAppear { isPlaying = commands.isPlaying }
    }

    @ViewBuilder private func control(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 2)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(.plain).help(help)
    }
}
