//
//  WebMDecoderTests.swift
//  IGramTests
//

import CoreGraphics
import Foundation
import Testing
@testable import IGram

/// The fixture is a 128×128, 30-frame VP9 WebM made with FFmpeg's libvpx-vp9
/// encoder (`-pix_fmt yuva420p`): the left half is opaque, the right half
/// fully transparent, like a Telegram video sticker.
struct WebMDecoderTests {
    private final class BundleToken {}

    private func fixture() throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "alpha-sticker", withExtension: "webm"))
        return try Data(contentsOf: url)
    }

    @Test func demuxesVideoTrackAndAlpha() throws {
        let demuxer = try WebMDemuxer(data: fixture())
        #expect(demuxer.codec == "V_VP9")
        #expect(demuxer.width == 128)
        #expect(demuxer.height == 128)
        #expect(demuxer.frames.count == 30)
        #expect(demuxer.frames.first?.isKeyframe == true)
        #expect(demuxer.frames.allSatisfy { $0.alpha != nil })
        #expect(abs(demuxer.duration - 1) < 0.01)
        #expect(zip(demuxer.frames, demuxer.frames.dropFirst()).allSatisfy { $0.time < $1.time })
    }

    @Test func rejectsOtherData() {
        #expect(throws: WebMDemuxer.Failure.notWebM) { try WebMDemuxer(data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])) }
        #expect(throws: WebMDemuxer.Failure.truncated) { try WebMDemuxer(data: Data()) }
    }

    @Test func readsVariableLengthSizes() throws {
        var reader = WebMDemuxer.Reader(bytes: [0x81, 0x40, 0x02, 0xFF, 0x1A, 0x45, 0xDF, 0xA3])
        #expect(try reader.readSize() == 1)
        #expect(try reader.readSize() == 2)
        #expect(try reader.readSize() == nil) // unknown size
        #expect(try reader.readID() == 0x1A45DFA3)
        #expect(reader.isAtEnd)
    }

    @Test func splitsSuperframes() {
        // Two frames of 3 and 2 bytes with a one-byte-per-size index.
        let marker: UInt8 = 0b1100_0001
        let packet = Data([0x82, 1, 2, 0x82, 3, marker, 3, 2, marker])
        let parts = VP9.split(packet)
        #expect(parts == [Data([0x82, 1, 2]), Data([0x82, 3])])
        #expect(VP9.split(Data([0x82, 1, 2])) == [Data([0x82, 1, 2])])
    }

    @Test func decodesFramesWithTransparency() throws {
        let decoder: WebMStickerDecoder
        do {
            decoder = try WebMStickerDecoder(data: fixture(), maxPixelSize: 64)
        } catch VP9Decoder.Failure.unavailable {
            return // No VP9 decoder on this Mac.
        }
        #expect(decoder.size.width == 64)
        let image = try #require(decoder.image(at: 5))
        let alpha = try alphaValues(of: image)
        #expect(alpha(8, 32) > 250)
        #expect(alpha(56, 32) < 5)
        // Looping back restarts from the first keyframe.
        #expect(decoder.image(at: 0) != nil)
        #expect(decoder.image(at: 29) != nil)
    }

    private func alphaValues(of image: CGImage) throws -> (Int, Int) -> UInt8 {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { raw in
            let context = try #require(CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return { x, y in pixels[(y * width + x) * 4 + 3] }
    }
}
