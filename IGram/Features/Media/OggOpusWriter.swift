//
//  OggOpusWriter.swift
//  IGram
//

import Foundation

/// Packs Opus packets into an Ogg stream (RFC 3533 pages, RFC 7845 headers).
///
/// Telegram voice messages must be Opus in Ogg. Apple's frameworks encode Opus
/// but cannot write Ogg, so this replaces the FFmpeg muxer tdesktop uses.
nonisolated struct OggOpusWriter {
    static let sampleRate: UInt32 = 48_000
    /// Opus encoder look-ahead at 48 kHz, skipped by decoders.
    static let preSkip: UInt16 = 312

    private(set) var data = Data()
    private let serial: UInt32
    private var sequence: UInt32 = 0
    private var granule: Int64 = 0
    private var pending: [Data] = []
    private var pendingSegments = 0

    init(channels: UInt8 = 1, serial: UInt32 = .random(in: 1...UInt32.max), vendor: String = "IGram") {
        self.serial = serial
        var head = Data("OpusHead".utf8)
        head.append(1)                                   // version
        head.append(channels)
        head.appendLittleEndian(Self.preSkip)
        head.appendLittleEndian(Self.sampleRate)
        head.appendLittleEndian(UInt16(0))               // output gain
        head.append(0)                                   // mapping family
        writePage(packets: [head], headerType: 0x02, granule: 0)

        var tags = Data("OpusTags".utf8)
        let vendorBytes = Data(vendor.utf8)
        tags.appendLittleEndian(UInt32(vendorBytes.count))
        tags.append(vendorBytes)
        tags.appendLittleEndian(UInt32(0))               // no user comments
        writePage(packets: [tags], headerType: 0, granule: 0)
    }

    /// Adds one Opus packet covering `frames` samples at 48 kHz.
    mutating func append(packet: Data, frames: Int) {
        let segments = packet.count / 255 + 1
        if pendingSegments + segments > 255 || pending.count >= 50 {
            flush(headerType: 0)
        }
        pending.append(packet)
        pendingSegments += segments
        granule += Int64(frames)
    }

    /// Writes the remaining packets with the end-of-stream flag.
    mutating func finish() -> Data {
        flush(headerType: 0x04, force: true)
        return data
    }

    private mutating func flush(headerType: UInt8, force: Bool = false) {
        guard !pending.isEmpty || force else { return }
        writePage(packets: pending, headerType: headerType, granule: granule)
        pending.removeAll()
        pendingSegments = 0
    }

    private mutating func writePage(packets: [Data], headerType: UInt8, granule: Int64) {
        var lacing: [UInt8] = []
        for packet in packets {
            lacing.append(contentsOf: Array(repeating: 255, count: packet.count / 255))
            lacing.append(UInt8(packet.count % 255))
        }
        var page = Data("OggS".utf8)
        page.append(0)                                   // stream structure version
        page.append(headerType)
        page.appendLittleEndian(UInt64(bitPattern: granule))
        page.appendLittleEndian(serial)
        page.appendLittleEndian(sequence)
        let crcOffset = page.count
        page.appendLittleEndian(UInt32(0))
        page.append(UInt8(lacing.count))
        page.append(contentsOf: lacing)
        for packet in packets { page.append(packet) }
        let crc = Self.crc(page)
        page.replaceSubrange(crcOffset..<crcOffset + 4, with: withUnsafeBytes(of: crc.littleEndian) { Data($0) })
        data.append(page)
        sequence += 1
    }

    // MARK: - CRC

    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index) << 24
        for _ in 0..<8 {
            value = value & 0x8000_0000 != 0 ? (value << 1) ^ 0x04C1_1DB7 : value << 1
        }
        return value
    }

    /// Ogg's CRC-32: polynomial 0x04C11DB7, no reflection, zero initial value.
    static func crc(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0
        for byte in bytes {
            crc = (crc << 8) ^ table[Int(((crc >> 24) & 0xFF) ^ UInt32(byte))]
        }
        return crc
    }
}

extension Data {
    nonisolated mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
