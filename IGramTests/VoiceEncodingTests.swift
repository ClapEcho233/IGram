//
//  VoiceEncodingTests.swift
//  IGramTests
//

import AVFoundation
import Foundation
import Testing
@testable import IGram

@MainActor
struct VoiceEncodingTests {
    private struct Page {
        let headerType: UInt8
        let granule: Int64
        let sequence: UInt32
        let packets: [Data]
        let crcMatches: Bool
    }

    /// A minimal Ogg reader used to check what the writer produces.
    private func pages(in data: Data) -> [Page] {
        let bytes = [UInt8](data)
        var pages: [Page] = []
        var offset = 0
        func u32(_ at: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(bytes[at + $1]) << (8 * $1) } }
        func u64(_ at: Int) -> UInt64 { (0..<8).reduce(0) { $0 | UInt64(bytes[at + $1]) << (8 * $1) } }
        while offset + 27 <= bytes.count, String(bytes: bytes[offset..<offset + 4], encoding: .ascii) == "OggS" {
            let segmentCount = Int(bytes[offset + 26])
            let lacing = Array(bytes[offset + 27..<offset + 27 + segmentCount])
            var cursor = offset + 27 + segmentCount
            var packets: [Data] = []
            var current = Data()
            for value in lacing {
                current.append(contentsOf: bytes[cursor..<cursor + Int(value)])
                cursor += Int(value)
                if value < 255 {
                    packets.append(current)
                    current = Data()
                }
            }
            var page = Data(bytes[offset..<cursor])
            let stored = u32(offset + 22)
            page.replaceSubrange(22..<26, with: [0, 0, 0, 0])
            pages.append(Page(
                headerType: bytes[offset + 5],
                granule: Int64(bitPattern: u64(offset + 6)),
                sequence: u32(offset + 18),
                packets: packets,
                crcMatches: OggOpusWriter.crc(page) == stored
            ))
            offset = cursor
        }
        return pages
    }

    @Test func crcOfKnownInput() {
        // Reference value from the Ogg specification's CRC (poly 0x04C11DB7, unreflected).
        #expect(OggOpusWriter.crc(Data("123456789".utf8)) == 0x89A1_897F)
    }

    @Test func writesHeadersAndPackets() {
        var writer = OggOpusWriter(serial: 7)
        for index in 0..<120 {
            writer.append(packet: Data(repeating: UInt8(index), count: index == 3 ? 600 : 40), frames: 960)
        }
        let result = pages(in: writer.finish())
        #expect(result.count >= 5)
        #expect(result.allSatisfy { $0.crcMatches })
        #expect(result.map(\.sequence) == Array(0..<UInt32(result.count)))
        #expect(result[0].headerType == 0x02)
        #expect(result[0].packets.first?.prefix(8) == Data("OpusHead".utf8))
        #expect(result[1].packets.first?.prefix(8) == Data("OpusTags".utf8))
        #expect(result.last?.headerType == 0x04)
        let expectedGranule: Int64 = 120 * 960
        #expect(result.last?.granule == expectedGranule)
        let audioPackets = result.dropFirst(2).flatMap(\.packets)
        #expect(audioPackets.count == 120)
        #expect(audioPackets[3].count == 600)
    }

    @Test func encodesToneIntoOggOpus() throws {
        let encoder = try OpusVoiceEncoder()
        let format = OpusVoiceEncoder.format
        for chunk in 0..<10 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800))
            buffer.frameLength = 4800
            let samples = try #require(buffer.floatChannelData?[0])
            for index in 0..<4800 {
                let t = Double(chunk * 4800 + index) / 48_000
                samples[index] = Float(sin(2 * .pi * 440 * t) * (Double(chunk) + 1) / 10)
            }
            encoder.encode(buffer)
        }
        let result = encoder.finish()
        let parsed = pages(in: result.data)
        #expect(parsed.allSatisfy { $0.crcMatches })
        #expect(parsed.dropFirst(2).flatMap(\.packets).count >= 45)
        #expect(Waveform.decode(result.waveform).count == 100)
        #expect(Waveform.decode(result.waveform).max() == 31)

        let url = FileManager.default.temporaryDirectory.appending(path: "igram-test-voice.ogg")
        try result.data.write(to: url)
    }

    @Test func waveformRoundTrip() {
        let values: [UInt8] = (0..<100).map { UInt8($0 % 32) }
        #expect(Waveform.decode(Waveform.encode(values)).prefix(100) == values[...])
    }
}
