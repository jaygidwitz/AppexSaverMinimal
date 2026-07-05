//
//  PreviewViewRepresentable.swift
//  AppexSaverMinimal
//
//  Copyright © 2026. Licensed under the MIT License.
//
//  SwiftUI wrapper embedding the AppKit PreviewView. Bump `reloadToken` to make
//  the preview rebuild from the current cache contents (after add/remove).
//

import SwiftUI

struct PreviewViewRepresentable: NSViewRepresentable {
    var reloadToken: Int = 0

    func makeNSView(context: Context) -> PreviewView { PreviewView() }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        if context.coordinator.lastToken != reloadToken {
            context.coordinator.lastToken = reloadToken
            nsView.reload()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(reloadToken) }

    final class Coordinator {
        var lastToken: Int
        init(_ token: Int) { lastToken = token }
    }
}
