//
//  VideoStickerView.swift
//  IGram
//

import AppKit
import CoreGraphics
import SwiftUI
@preconcurrency import TDLibKit

/// A looping WebM sticker, decoded with VideoToolbox frame by frame.
/// Falls back to `placeholder` until the file is downloaded, or for good if
/// this Mac has no VP9 decoder.
///
/// Frames go straight into a layer rather than through SwiftUI state, so a
/// few looping stickers don't run a view update 30 times a second each while
/// the history scrolls.
struct VideoStickerView<Placeholder: View>: View {
    let file: File
    var maxPixelSize = 360
    var loops = true
    @ViewBuilder var placeholder: Placeholder

    @Environment(TelegramSession.self) private var session
    @State private var sink = StickerFrameSink()
    @State private var hasFrame = false

    private struct SendableImage: @unchecked Sendable {
        let image: CGImage?
    }

    var body: some View {
        let item = session.files.item(for: file)
        ZStack {
            if hasFrame {
                StickerFrameLayer(sink: sink)
            } else {
                placeholder
            }
        }
        .task(id: item.localURL) {
            guard let url = item.localURL else {
                session.files.download(file, priority: .media)
                return
            }
            await play(url)
        }
    }

    private func play(_ url: URL) async {
        let size = maxPixelSize
        let decoder = await Task.detached(priority: .userInitiated) {
            try? WebMStickerDecoder(data: Data(contentsOf: url), maxPixelSize: size)
        }.value
        guard let decoder, decoder.frameCount > 0 else { return }
        let clock = ContinuousClock()
        var deadline = clock.now
        var index = 0
        while !Task.isCancelled {
            let current = index
            let rendered = await Task.detached(priority: .userInitiated) {
                SendableImage(image: decoder.image(at: current))
            }.value
            if let image = rendered.image {
                sink.show(image)
                if !hasFrame { hasFrame = true }
            }
            if decoder.frameCount == 1 { return }
            deadline += .seconds(decoder.demuxer.durations[current])
            // After a stall, resynchronize instead of rushing through frames.
            if deadline < clock.now { deadline = clock.now }
            do { try await Task.sleep(until: deadline, clock: clock) } catch { return }
            index += 1
            if index == decoder.frameCount {
                guard loops else { return }
                index = 0
            }
        }
    }
}

/// Hands decoded sticker frames to the layer showing them.
@MainActor
final class StickerFrameSink {
    fileprivate weak var layer: CALayer?
    fileprivate private(set) var lastFrame: CGImage?

    func show(_ image: CGImage) {
        lastFrame = image
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }
}

private struct StickerFrameLayer: NSViewRepresentable {
    let sink: StickerFrameSink

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resizeAspect
        view.layer?.contents = sink.lastFrame
        sink.layer = view.layer
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        sink.layer = view.layer
    }
}
