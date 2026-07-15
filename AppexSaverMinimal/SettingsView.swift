//
//  SettingsView.swift
//  Surrealism
//
//  The app Settings panel (App menu → Settings…, ⌘,) via the SwiftUI Settings
//  scene. Holds preferences that aren't day-to-day playback controls — power
//  courtesy and the telemetry opt-out — so the Playback panel stays about
//  what's on screen. Styled to match the in-app panels (dark, violet accent).
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: PlaybackSettings
    @ObservedObject private var telemetry = Telemetry.shared

    private let accent = Color(red: 0.55, green: 0.4, blue: 0.95)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SurrealismMark(size: 22)
                Text("Settings").font(.system(size: 17, weight: .semibold))
                Spacer()
            }

            Toggle(isOn: Binding(get: { settings.courtesyEnabled },
                                 set: { settings.setCourtesyEnabled($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pause wallpaper on battery").font(.system(size: 14, weight: .medium))
                    Text("Saves power — also pauses when the Mac is thermally stressed")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(accent)

            Toggle(isOn: Binding(get: { telemetry.enabled },
                                 set: { telemetry.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Share anonymous usage data").font(.system(size: 14, weight: .medium))
                    Text("Feature-usage counts only — never your loops, key, or email")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(accent)
        }
        .padding(22)
        .frame(width: 460)
        .background(Color(red: 0.055, green: 0.04, blue: 0.09))
        .preferredColorScheme(.dark)
    }
}
