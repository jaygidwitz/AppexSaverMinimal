//
//  AppexSaverApp.swift
//  AppexSaver
//
//  Host application for the screensaver extension.
//  This minimal app exists to bundle and distribute the screensaver appex.
//

import SwiftUI

@main
struct AppexSaverApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        Window("Preview", id: "preview") {
            PreviewViewRepresentable()
                .ignoresSafeArea()
        }
        .defaultSize(width: 640, height: 480)
    }
}
