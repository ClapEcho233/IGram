//
//  LoopingVideoView.swift
//  IGram
//

import AVFoundation
import AppKit
import SwiftUI

/// A muted, looping inline video for GIFs, like tdesktop's autoplaying animations.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.play(url)
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {
        if view.currentURL != url { view.play(url) }
    }

    static func dismantleNSView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: NSView {
        private let playerLayer = AVPlayerLayer()
        private var looper: AVPlayerLooper?
        private(set) var currentURL: URL?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }

        func play(_ url: URL) {
            currentURL = url
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            playerLayer.player = player
            player.play()
        }

        func stop() {
            playerLayer.player?.pause()
            playerLayer.player = nil
            looper = nil
        }
    }
}
