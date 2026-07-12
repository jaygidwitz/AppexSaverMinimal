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

    private let chipColumns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SurrealismMark(size: 22)
                Text("Playback").font(.system(size: 17, weight: .semibold))
                Spacer()
            }

            Toggle(isOn: Binding(get: { settings.shuffle }, set: { settings.setShuffle($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Shuffle").font(.system(size: 14, weight: .medium))
                    Text(settings.shuffle ? "Random order" : "In order")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(Color(red: 0.55, green: 0.4, blue: 0.95))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Cross-fade").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text(String(format: "%.1fs", settings.crossFadeSeconds))
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { settings.crossFadeSeconds },
                                      set: { settings.setCrossFadeSeconds($0) }),
                       in: PlaybackSettings.fadeRange)
                    .tint(Color(red: 0.55, green: 0.4, blue: 0.95))
            }

            if !videos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("In rotation").font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(rotationSummary).font(.system(size: 12)).foregroundStyle(.secondary)
                        if !settings.rotation.isEmpty {
                            Button("All") { settings.setRotation([]) }
                                .buttonStyle(GhostButtonStyle()).controlSize(.small)
                        }
                    }
                    LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                        ForEach(videos) { video in
                            chip(for: video)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private var rotationSummary: String {
        settings.rotation.isEmpty ? "All \(videos.count) loops" : "\(inRotationCount) of \(videos.count)"
    }

    /// How many of the *current* library are selected (ignores stale ids).
    private var inRotationCount: Int {
        videos.filter { settings.rotation.contains(RotationResolver.identifier(for: $0.url)) }.count
    }

    @ViewBuilder private func chip(for video: LibraryVideo) -> some View {
        let id = RotationResolver.identifier(for: video.url)
        // Empty rotation = all loops, so every chip reads as "on" in that state.
        let on = settings.rotation.isEmpty || settings.rotation.contains(id)
        Button { settings.toggle(id) } label: {
            Text(video.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(on ? Color(red: 0.45, green: 0.3, blue: 0.9).opacity(0.35)
                                       : Color.white.opacity(0.05))
                )
                .overlay(Capsule().strokeBorder(on ? Color(red: 0.6, green: 0.45, blue: 0.95).opacity(0.6)
                                                    : .white.opacity(0.12), lineWidth: 1))
                .foregroundStyle(on ? .white : .secondary)
        }
        .buttonStyle(.plain)
    }
}
