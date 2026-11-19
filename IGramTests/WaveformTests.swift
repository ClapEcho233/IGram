//
//  WaveformTests.swift
//  IGramTests
//

import Foundation
import Testing
@testable import IGram

@MainActor
struct WaveformTests {
    /// Packs 5-bit values the way Telegram clients encode waveforms.
    private func encode(_ values: [UInt8]) -> Data {
        var bytes = [UInt8](repeating: 0, count: (values.count * 5 + 7) / 8)
        for (index, value) in values.enumerated() {
            let bitOffset = index * 5
            let packed = UInt16(value & 0x1F) << UInt16(bitOffset % 8)
            bytes[bitOffset / 8] |= UInt8(packed & 0xFF)
            if bitOffset / 8 + 1 < bytes.count {
                bytes[bitOffset / 8 + 1] |= UInt8(packed >> 8)
            }
        }
        return Data(bytes)
    }

    @Test func decodesPackedSamples() {
        let values: [UInt8] = [0, 31, 7, 16, 3, 30, 1, 22]
        #expect(Waveform.decode(encode(values)) == values)
    }

    @Test func emptyWaveform() {
        #expect(Waveform.decode(Data()).isEmpty)
        #expect(Waveform.resample([], to: 4) == [0, 0, 0, 0])
    }

    @Test func resampleKeepsPeaks() {
        #expect(Waveform.resample([1, 9, 2, 3, 8, 4], to: 3) == [9, 3, 8])
        #expect(Waveform.resample([5, 6], to: 4).count == 4)
    }
}
