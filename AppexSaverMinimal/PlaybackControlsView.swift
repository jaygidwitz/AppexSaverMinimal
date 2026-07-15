//
//  PlaybackControlsView.swift
//  Surrealism
//
//  Host-window "Playback" panel: shuffle, cross-fade duration, and which loops
//  are in rotation. Two-way bound to the shared PlaybackSettings so edits persist
//  (R8) and propagate live to the running player (U6). See plan U5.
//

import SwiftUI

struct PlaybackControlsView: View {
    @ObservedObject var settings: PlaybackSettings
    let videos: [LibraryVideo]
    /// "Choose Loops" mode, owned by ContentView (KTD2). The panel flips it; the
    /// library grid reads it to switch tile behavior.
    @Binding var isSelecting: Bool

    private let accent = Color(red: 0.55, green: 0.4, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SurrealismMark(size: 22)
                Text("Playback").font(.system(size: 17, weight: .semibold))
                Spacer()
            }

            HStack(spacing: 12) {
                Toggle(isOn: Binding(get: { settings.shuffle }, set: { settings.setShuffle($0) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Shuffle").font(.system(size: 14, weight: .medium))
                        Text(settings.shuffle ? "Random order" : "In order")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)

                Spacer()

                // Cross-fade as a compact value + stepper (steps match the [ ] keys).
                Text("Cross-fade").font(.system(size: 14, weight: .medium))
                Text(String(format: "%.1fs", settings.crossFadeSeconds))
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(minWidth: 34, alignment: .trailing)
                Stepper("Cross-fade",
                        value: Binding(get: { settings.crossFadeSeconds },
                                       set: { settings.setCrossFadeSeconds($0) }),
                        in: PlaybackSettings.fadeRange,
                        step: PlaybackCommands.crossFadeStepSeconds)
                    .labelsHidden()
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Speed").font(.system(size: 14, weight: .medium))
                    Text("Slow the motion down — applies everywhere")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(speedLabel)
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                    .frame(minWidth: 52, alignment: .trailing)
                Stepper("Speed",
                        value: Binding(get: { settings.playbackRate },
                                       set: { settings.setPlaybackRate($0) }),
                        in: PlaybackSettings.rateRange,
                        step: 0.05)
                    .labelsHidden()
            }

            if !videos.isEmpty {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("In rotation").font(.system(size: 14, weight: .medium))
                        Text(rotationSummary).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelecting && !settings.rotation.isEmpty {
                        Button("All") { settings.setRotation([]) }
                            .buttonStyle(GhostButtonStyle()).controlSize(.small)
                    }
                    Button(isSelecting ? "Done" : "Choose…") { isSelecting.toggle() }
                        .buttonStyle(GhostButtonStyle()).controlSize(.small)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private var speedLabel: String {
        settings.playbackRate >= 0.999 ? "Normal" : String(format: "%.2f×", settings.playbackRate)
    }

    private var rotationSummary: String {
        settings.rotation.isEmpty
            ? "All \(videos.count) loops"
            : "\(inRotationCount) of \(videos.count) loops"
    }

    /// How many of the *current* library are selected (ignores stale ids).
    private var inRotationCount: Int {
        videos.filter { settings.rotation.contains(RotationResolver.identifier(for: $0.url)) }.count
    }
}
