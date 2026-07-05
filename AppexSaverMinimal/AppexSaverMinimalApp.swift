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

@main
struct AppexSaverMinimalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
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
