//
//  VideoStickerView.swift
//  IGram
//

import CoreGraphics
import SwiftUI
@preconcurrency import TDLibKit

/// A looping WebM sticker, decoded with VideoToolbox frame by frame.
/// Falls back to `placeholder` until the file is downloaded, or for good if
/// this Mac has no VP9 decoder.
struct VideoStickerView<Placeholder: View>: View {
    let file: File
    var maxPixelSize = 360
    var loops = true
    @ViewBuilder var placeholder: Placeholder

    @Environment(TelegramSession.self) private var session
    @State private var frame: CGImage?

    private struct SendableImage: @unchecked Sendable {
        let image: CGImage?
    }

    var body: some View {
        let item = session.files.item(for: file)
        ZStack {
            if let frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
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
            if let image = rendered.image { frame = image }
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
