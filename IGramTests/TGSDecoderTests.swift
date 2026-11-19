//
//  TGSDecoderTests.swift
//  IGramTests
//

import Foundation
import Testing
@testable import IGram

@MainActor
struct TGSDecoderTests {
    private let json = Data(#"{"v":"5.5.2","fr":60,"ip":0,"op":180,"w":512,"h":512,"nm":"t","ddd":0,"assets":[],"layers":[]}"#.utf8)

    /// Wraps raw DEFLATE data in a gzip header and trailer, with a file name to
    /// exercise the optional-field parsing.
    private func gzip(_ data: Data) throws -> Data {
        var result = Data([0x1F, 0x8B, 0x08, 0x08, 0, 0, 0, 0, 0, 0x03])
        result.append(Data("sticker.json".utf8))
        result.append(0)
        result.append(try (data as NSData).compressed(using: .zlib) as Data)
        result.append(contentsOf: [0, 0, 0, 0])
        result.append(contentsOf: withUnsafeBytes(of: UInt32(data.count).littleEndian) { Array($0) })
        return result
    }

    @Test func gunzipRoundTrip() throws {
        #expect(TGSDecoder.gunzip(try gzip(json)) == json)
    }

    @Test func rejectsNonGzipData() {
        #expect(TGSDecoder.gunzip(json) == nil)
    }

    @Test func decodesLottieAnimation() throws {
        #expect(TGSDecoder.decode(try gzip(json)) != nil)
        #expect(TGSDecoder.decode(Data("not json".utf8)) == nil)
    }
}
