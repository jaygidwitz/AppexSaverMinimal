//
//  PlaybackControlsView.swift
//  Surrealism
//
//  Host-window "Playback" panel: shuffle, cross-fade duration, and which loops
//  are in rotation. Two-way bound to the shared PlaybackSettings so edits persist
//  (R8) and propagate live to the running player (U6). See plan U5.
//
//  Collapsible — starts collapsed each launch with a one-line state summary in
//  the header; the whole header row is the toggle.
//

import SwiftUI

struct PlaybackControlsView<Footer: View>: View {
    @ObservedObject var settings: PlaybackSettings
    let videos: [LibraryVideo]
    /// "Choose Loops" mode, owned by ContentView (KTD2). The panel flips it; the
    /// library grid reads it to switch tile behavior.
    @Binding var isSelecting: Bool
    /// Extra section rendered at the bottom of the expanded panel — ContentView
    /// passes the Screensaver setup/status rows so their PluginManager logic
    /// stays with it.
    @ViewBuilder var footer: () -> Footer
    /// Collapsed by default each launch — the header row expands it.
    @State private var expanded = false

    private let accent = Color(red: 0.55, green: 0.4, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if expanded {
                shuffleAndCrossFadeRow
                speedRow
                if !videos.isEmpty { rotationRow }
                Divider().overlay(.white.opacity(0.08))
                footer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: Rows

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                expanded.toggle()
                if !expanded { isSelecting = false }  // don't strand Choose-Loops mode
            }
        } label: {
            HStack(spacing: 12) {
                SurrealismMark(size: 22)
                Text("Playback").font(.system(size: 17, weight: .semibold))
                if !expanded {
                    Text(collapsedSummary)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var shuffleAndCrossFadeRow: some View {
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
    }

    private var speedRow: some View {
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
    }

    private var rotationRow: some View {
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

    // MARK: Labels

    private var speedLabel: String {
        settings.playbackRate >= 0.999 ? "Normal" : String(format: "%.2f×", settings.playbackRate)
    }

    /// One-line state readout for the collapsed header.
    private var collapsedSummary: String {
        var parts = [settings.shuffle ? "Shuffle" : "In order",
                     String(format: "%.1fs fade", settings.crossFadeSeconds)]
        if settings.playbackRate < 0.999 { parts.append(speedLabel) }
        if !videos.isEmpty { parts.append(rotationSummary.lowercased()) }
        return parts.joined(separator: " · ")
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
