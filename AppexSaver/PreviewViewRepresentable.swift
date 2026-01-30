//
//  PreviewViewRepresentable.swift
//  AppexSaver
//
//  SwiftUI wrapper for PreviewView to use in the preview window.
//

import SwiftUI

/// SwiftUI wrapper for the PreviewView NSView.
struct PreviewViewRepresentable: NSViewRepresentable {

    func makeNSView(context: Context) -> PreviewView {
        PreviewView()
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        // No updates needed
    }
}
