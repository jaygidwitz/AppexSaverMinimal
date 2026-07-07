//
//  LoopPreviewView.swift
//  Surrealism · Commerce
//
//  Lightweight looping, muted, controls-free video layer for catalog hover
//  previews. Streams a short preview clip from the site.
//

import SwiftUI
import AVFoundation
import AppKit

struct LoopPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PreviewPlayerView {
        let view = PreviewPlayerView()
        view.load(url: url)
        return view
    }
    func updateNSView(_ nsView: PreviewPlayerView, context: Context) {}
    static func dismantleNSView(_ nsView: PreviewPlayerView, coordinator: ()) { nsView.stop() }
}

final class PreviewPlayerView: NSView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    override func layout() { super.layout(); playerLayer.frame = bounds }

    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        playerLayer.player = queue
        player = queue
        queue.play()
    }

    func stop() {
        player?.pause()
        playerLayer.player = nil
        looper = nil
        player = nil
    }
}
