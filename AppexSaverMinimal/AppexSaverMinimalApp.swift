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

extension ProcessInfo {
    /// True when the process was launched by XCTest (the app is acting as the
    /// unit-test host). XCTest sets `XCTestConfigurationFilePath` in the
    /// environment of the host it injects into.
    var isRunningUnitTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}

/// App-level delegate so the magic-link callback (surrealism://auth/callback) is
/// handled once at the process level and routed to the shared LicenseStore —
/// instead of a per-window `.onOpenURL`, which spawns a second window and hits a
/// different store instance than the one showing "Check your email".
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let license = LicenseStore()
    /// Shared playback settings (shuffle / cross-fade / rotation), app-owned so
    /// every surface observes one source of truth.
    let playback = PlaybackSettings()

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
            // As the unit-test host, don't mount the real UI: ContentView's
            // launch `.task` (license revalidation) and CatalogView's catalog
            // load fire real network requests that hang the test host offline.
            // Tests build their own objects via `@testable import`, so the
            // window content is irrelevant to them.
            if ProcessInfo.processInfo.isRunningUnitTests {
                EmptyView()
            } else {
                ContentView()
                    .environmentObject(appDelegate.license)
                    .environmentObject(appDelegate.playback)
                    // Let the existing window claim external (surrealism://) events so a
                    // magic-link open reuses this window instead of spawning a new one.
                    .handlesExternalEvents(preferring: ["main"], allowing: ["*"])
            }
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
