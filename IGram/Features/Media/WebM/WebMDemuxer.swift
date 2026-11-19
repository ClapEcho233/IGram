//
//  WebMDemuxer.swift
//  IGram
//

import Foundation

/// Reads the video frames of a WebM (Matroska) file, enough for Telegram's
/// video stickers and emoji: one VP9 track whose alpha channel, if any, is a
/// second VP9 stream stored in each block's `BlockAdditional`.
///
/// tdesktop plays these with FFmpeg; macOS has a VP9 decoder in VideoToolbox
/// but no WebM demuxer, so IGram parses the container itself.
nonisolated struct WebMDemuxer: Sendable {
    struct Frame: Sendable, Equatable {
        /// Presentation time in seconds from the start.
        let time: Double
        let data: Data
        /// The VP9 frame carrying the alpha plane in its luma, if present.
        let alpha: Data?
        let isKeyframe: Bool
    }

    enum Failure: Error, Equatable {
        case notWebM
        case truncated
        case noVideoTrack
    }

    let codec: String
    let width: Int
    let height: Int
    let frames: [Frame]
    /// Seconds each frame stays on screen, parallel to `frames`.
    let durations: [Double]

    var duration: Double { durations.reduce(0, +) }

    // MARK: - Element IDs (Matroska specification)

    private enum ID {
        static let ebml: UInt32 = 0x1A45DFA3
        static let segment: UInt32 = 0x18538067
        static let info: UInt32 = 0x1549A966
        static let timecodeScale: UInt32 = 0x2AD7B1
        static let tracks: UInt32 = 0x1654AE6B
        static let trackEntry: UInt32 = 0xAE
        static let trackNumber: UInt32 = 0xD7
        static let trackType: UInt32 = 0x83
        static let codecID: UInt32 = 0x86
        static let defaultDuration: UInt32 = 0x23E383
        static let video: UInt32 = 0xE0
        static let pixelWidth: UInt32 = 0xB0
        static let pixelHeight: UInt32 = 0xBA
        static let cluster: UInt32 = 0x1F43B675
        static let timecode: UInt32 = 0xE7
        static let simpleBlock: UInt32 = 0xA3
        static let blockGroup: UInt32 = 0xA0
        static let block: UInt32 = 0xA1
        static let blockAdditions: UInt32 = 0x75A1
        static let blockMore: UInt32 = 0xA6
        static let blockAddID: UInt32 = 0xEE
        static let blockAdditional: UInt32 = 0xA5
    }

    /// Masters whose children are read in place rather than skipped.
    private static let flattened: Set<UInt32> = [ID.segment, ID.info, ID.tracks, ID.video, ID.cluster]

    private struct Track {
        var number: UInt64 = 0
        var type: UInt64 = 0
        var codec = ""
        var width = 0
        var height = 0
        var defaultDuration: UInt64 = 0
    }

    private struct RawFrame {
        let track: UInt64
        let timecode: Int64
        let data: Data
        let alpha: Data?
        let isKeyframe: Bool
    }

    init(data: Data) throws {
        var reader = Reader(bytes: [UInt8](data))
        guard try reader.readID() == ID.ebml else { throw Failure.notWebM }
        let headerSize = try reader.readSize()
        try reader.skip(headerSize ?? 0)

        var timecodeScale: UInt64 = 1_000_000
        var tracks: [Track] = []
        var clusterTimecode: Int64 = 0
        var raw: [RawFrame] = []

        while !reader.isAtEnd {
            let id = try reader.readID()
            let size = try reader.readSize()
            if Self.flattened.contains(id) { continue }
            guard let size else {
                // Only the masters above may have an unknown size.
                throw Failure.truncated
            }
            let body = try reader.take(size)
            switch id {
            case ID.timecodeScale:
                timecodeScale = Self.unsigned(body)
            case ID.trackEntry:
                tracks.append(try Self.parseTrack(body))
            case ID.timecode:
                clusterTimecode = Int64(Self.unsigned(body))
            case ID.simpleBlock:
                if let frame = try Self.parseBlock(body, clusterTimecode: clusterTimecode, alpha: nil, simple: true) {
                    raw.append(frame)
                }
            case ID.blockGroup:
                if let frame = try Self.parseBlockGroup(body, clusterTimecode: clusterTimecode) {
                    raw.append(frame)
                }
            default:
                break
            }
        }

        guard let track = tracks.first(where: { $0.type == 1 || $0.codec.hasPrefix("V_") }) else {
            throw Failure.noVideoTrack
        }
        let scale = Double(timecodeScale) / 1_000_000_000
        let frames = raw
            .filter { $0.track == track.number }
            .map { Frame(time: Double($0.timecode) * scale, data: $0.data, alpha: $0.alpha, isKeyframe: $0.isKeyframe) }
            .sorted { $0.time < $1.time }
        guard !frames.isEmpty else { throw Failure.noVideoTrack }

        let fallback = track.defaultDuration > 0 ? Double(track.defaultDuration) / 1_000_000_000 : 1.0 / 30
        var durations: [Double] = []
        for index in frames.indices {
            if index + 1 < frames.count {
                let gap = frames[index + 1].time - frames[index].time
                durations.append(gap > 0 ? gap : fallback)
            } else {
                durations.append(fallback)
            }
        }

        codec = track.codec
        width = track.width
        height = track.height
        self.frames = frames
        self.durations = durations
    }

    private static func parseTrack(_ bytes: ArraySlice<UInt8>) throws -> Track {
        var track = Track()
        var reader = Reader(bytes: Array(bytes))
        while !reader.isAtEnd {
            let id = try reader.readID()
            guard let size = try reader.readSize() else { throw Failure.truncated }
            if id == ID.video { continue }
            let body = try reader.take(size)
            switch id {
            case ID.trackNumber: track.number = unsigned(body)
            case ID.trackType: track.type = unsigned(body)
            case ID.codecID: track.codec = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
            case ID.defaultDuration: track.defaultDuration = unsigned(body)
            case ID.pixelWidth: track.width = Int(unsigned(body))
            case ID.pixelHeight: track.height = Int(unsigned(body))
            default: break
            }
        }
        return track
    }

    private static func parseBlockGroup(_ bytes: ArraySlice<UInt8>, clusterTimecode: Int64) throws -> RawFrame? {
        var reader = Reader(bytes: Array(bytes))
        var block: ArraySlice<UInt8>?
        var alpha: Data?
        while !reader.isAtEnd {
            let id = try reader.readID()
            guard let size = try reader.readSize() else { throw Failure.truncated }
            if id == ID.blockAdditions { continue }
            let body = try reader.take(size)
            switch id {
            case ID.block:
                block = body
            case ID.blockMore:
                if let candidate = try parseBlockMore(body) { alpha = candidate }
            default:
                break
            }
        }
        guard let block else { return nil }
        return try parseBlock(block, clusterTimecode: clusterTimecode, alpha: alpha, simple: false)
    }

    private static func parseBlockMore(_ bytes: ArraySlice<UInt8>) throws -> Data? {
        var reader = Reader(bytes: Array(bytes))
        // Per Matroska spec, BlockAddID defaults to 1 (used by WebM alpha).
        var addID: UInt64 = 1
        var additional: Data?
        while !reader.isAtEnd {
            let id = try reader.readID()
            guard let size = try reader.readSize() else { throw Failure.truncated }
            let body = try reader.take(size)
            switch id {
            case ID.blockAddID: addID = unsigned(body)
            case ID.blockAdditional: additional = Data(body)
            default: break
            }
        }
        return addID == 1 ? additional : nil
    }

    private static func parseBlock(_ bytes: ArraySlice<UInt8>, clusterTimecode: Int64, alpha: Data?, simple: Bool) throws -> RawFrame? {
        var reader = Reader(bytes: Array(bytes))
        guard let track = try reader.readSize() else { throw Failure.truncated }
        let timing = try reader.take(2)
        let relative = Int16(bitPattern: UInt16(timing[timing.startIndex]) << 8 | UInt16(timing[timing.startIndex + 1]))
        let flags = try reader.take(1)[reader.offset - 1]
        // Lacing packs several frames per block; video tracks never use it.
        guard flags & 0x06 == 0 else { return nil }
        let payload = Data(try reader.take(UInt64(reader.remaining)))
        let isKeyframe = simple ? flags & 0x80 != 0 : VP9.isKeyframe(payload)
        return RawFrame(
            track: track,
            timecode: clusterTimecode + Int64(relative),
            data: payload,
            alpha: alpha,
            isKeyframe: isKeyframe
        )
    }

    static func unsigned(_ bytes: ArraySlice<UInt8>) -> UInt64 {
        bytes.reduce(0) { $0 << 8 | UInt64($1) }
    }

    // MARK: - EBML reader

    struct Reader {
        let bytes: [UInt8]
        var offset = 0

        var isAtEnd: Bool { offset >= bytes.count }
        var remaining: Int { bytes.count - offset }

        /// An element ID keeps its length marker bits.
        mutating func readID() throws -> UInt32 {
            guard offset < bytes.count else { throw Failure.truncated }
            let first = bytes[offset]
            let length = first.leadingZeroBitCount + 1
            guard length <= 4, offset + length <= bytes.count else { throw Failure.truncated }
            var value: UInt32 = 0
            for index in 0..<length {
                value = value << 8 | UInt32(bytes[offset + index])
            }
            offset += length
            return value
        }

        /// A variable-length size; nil means "unknown" (all value bits set).
        mutating func readSize() throws -> UInt64? {
            guard offset < bytes.count else { throw Failure.truncated }
            let first = bytes[offset]
            guard first != 0 else { throw Failure.truncated }
            let length = first.leadingZeroBitCount + 1
            guard offset + length <= bytes.count else { throw Failure.truncated }
            var value = UInt64(first & (0xFF >> length))
            var allOnes = value == UInt64(0xFF >> length)
            for index in 1..<length {
                let byte = bytes[offset + index]
                allOnes = allOnes && byte == 0xFF
                value = value << 8 | UInt64(byte)
            }
            offset += length
            return allOnes ? nil : value
        }

        mutating func take(_ count: UInt64) throws -> ArraySlice<UInt8> {
            guard count <= UInt64(remaining) else { throw Failure.truncated }
            let end = offset + Int(count)
            defer { offset = end }
            return bytes[offset..<end]
        }

        mutating func skip(_ count: UInt64) throws {
            _ = try take(count)
        }
    }
}

/// Bits of the VP9 bitstream needed to configure a decoder.
nonisolated enum VP9 {
    /// The profile from the first byte of the uncompressed header.
    static func profile(_ frame: Data) -> Int {
        guard let first = frame.first else { return 0 }
        let low = Int(first >> 5) & 1
        let high = Int(first >> 4) & 1
        return high << 1 | low
    }

    /// A keyframe has `frame_type` 0 and isn't a "show existing frame" packet.
    static func isKeyframe(_ frame: Data) -> Bool {
        guard let first = frame.first, first >> 6 == 0b10 else { return false }
        // Bits from the top: marker (2), profile (2), a reserved bit in
        // profile 3, show_existing_frame, then frame_type.
        let showExisting = profile(frame) == 3 ? 5 : 4
        func bit(_ index: Int) -> Int { Int(first) >> (7 - index) & 1 }
        return bit(showExisting) == 0 && bit(showExisting + 1) == 0
    }

    /// Splits a superframe (several frames sharing one packet) into its frames.
    static func split(_ packet: Data) -> [Data] {
        let bytes = [UInt8](packet)
        guard let marker = bytes.last, marker & 0xE0 == 0xC0 else { return [packet] }
        let count = Int(marker & 0x07) + 1
        let sizeBytes = Int((marker >> 3) & 0x03) + 1
        let indexSize = 2 + sizeBytes * count
        guard bytes.count >= indexSize, bytes[bytes.count - indexSize] == marker else { return [packet] }
        var frames: [Data] = []
        var offset = 0
        var cursor = bytes.count - indexSize + 1
        for _ in 0..<count {
            var size = 0
            for byte in 0..<sizeBytes {
                size |= Int(bytes[cursor + byte]) << (8 * byte)
            }
            cursor += sizeBytes
            guard size > 0, offset + size <= bytes.count - indexSize else { return [packet] }
            frames.append(Data(bytes[offset..<(offset + size)]))
            offset += size
        }
        return frames
    }
}
