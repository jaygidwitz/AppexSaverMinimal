//
//  AppexSaverMinimalApp.swift
//  AppexSaverMinimal
//
//  Copyright © 2026 Guillaume Louel. Licensed under the MIT License.
//
//  Host application for the screensaver extension. The host app exists so the
//  .appex can be bundled and registered with pluginkit; macOS does not load
//  appex bundles that aren't embedded inside an application.
//

import SwiftUI

/// App-level delegate so the magic-link callback (surrealism://auth/callback) is
/// handled once at the process level and routed to the shared LicenseStore —
/// instead of a per-window `.onOpenURL`, which spawns a second window and hits a
/// different store instance than the one showing "Check your email".
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let license = LicenseStore()

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await license.handleAuthCallback(url) }
        }
    }
}

@main
struct AppexSaverMinimalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.license)
                // Let the existing window claim external (surrealism://) events so a
                // magic-link open reuses this window instead of spawning a new one.
                .handlesExternalEvents(preferring: ["main"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["main"])
        .defaultSize(width: 720, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Surrealism Help") {
                    if let url = URL(string: "https://surrealism.app") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        Window("Preview", id: "preview") {
            PreviewViewRepresentable()
                .ignoresSafeArea()
        }
        .defaultSize(width: 640, height: 480)
    }
}
