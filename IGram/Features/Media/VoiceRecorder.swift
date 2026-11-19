//
//  VoiceRecorder.swift
//  IGram
//

import AVFoundation
import Foundation
import OSLog

/// A finished voice message ready to send.
nonisolated struct RecordedVoice: Sendable {
    let url: URL
    let duration: Int
    let waveform: Data
}

/// Encodes 48 kHz mono PCM into an Ogg Opus voice message and its waveform.
nonisolated final class OpusVoiceEncoder {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    static let framesPerPacket: UInt32 = 960

    private let converter: AVAudioConverter
    private let opusFormat: AVAudioFormat
    private var writer = OggOpusWriter()
    private(set) var sampleCount: Int64 = 0
    private var peaks: [Float] = []
    private var chunkPeak: Float = 0
    private var chunkFrames = 0

    init() throws {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: Self.framesPerPacket,
            mBytesPerFrame: 0,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        guard let opusFormat = AVAudioFormat(streamDescription: &description),
              let converter = AVAudioConverter(from: Self.format, to: opusFormat)
        else { throw CocoaError(.featureUnsupported) }
        converter.bitRate = 32_000
        self.opusFormat = opusFormat
        self.converter = converter
    }

    /// Encodes `buffer` (48 kHz mono float).
    func encode(_ buffer: AVAudioPCMBuffer) {
        track(buffer)
        sampleCount += Int64(buffer.frameLength)
        drain(input: buffer, endOfStream: false)
    }

    /// Flushes the encoder and returns the Ogg file contents and waveform.
    func finish() -> (data: Data, waveform: Data) {
        drain(input: nil, endOfStream: true)
        if chunkFrames > 0 { peaks.append(chunkPeak) }
        return (writer.finish(), Self.waveform(from: peaks))
    }

    /// Current input level in `0...1`, for the recording indicator.
    private(set) var level: Float = 0

    private func drain(input: AVAudioPCMBuffer?, endOfStream: Bool) {
        var supplied = false
        while true {
            let output = AVAudioCompressedBuffer(
                format: opusFormat,
                packetCapacity: 16,
                maximumPacketSize: max(converter.maximumOutputPacketSize, 1500)
            )
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if let input, !supplied {
                    supplied = true
                    inputStatus.pointee = .haveData
                    return input
                }
                inputStatus.pointee = endOfStream ? .endOfStream : .noDataNow
                return nil
            }
            if let error {
                Log.ui.error("Opus encoding failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            append(output)
            if status != .haveData { return }
        }
    }

    private func append(_ buffer: AVAudioCompressedBuffer) {
        guard let descriptions = buffer.packetDescriptions else { return }
        for index in 0..<Int(buffer.packetCount) {
            let description = descriptions[index]
            let bytes = UnsafeRawPointer(buffer.data).advanced(by: Int(description.mStartOffset))
            writer.append(packet: Data(bytes: bytes, count: Int(description.mDataByteSize)), frames: Int(Self.framesPerPacket))
        }
    }

    private func track(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        var bufferPeak: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let value = abs(samples[index])
            bufferPeak = max(bufferPeak, value)
            chunkPeak = max(chunkPeak, value)
            chunkFrames += 1
            if chunkFrames == 4800 {
                peaks.append(chunkPeak)
                chunkPeak = 0
                chunkFrames = 0
            }
        }
        level = min(bufferPeak * 1.6, 1)
    }

    /// 100 five-bit samples normalized to the loudest chunk, as Telegram expects.
    static func waveform(from peaks: [Float]) -> Data {
        guard let loudest = peaks.max(), loudest > 0 else { return Waveform.encode(Array(repeating: 0, count: 100)) }
        let scaled = peaks.map { UInt8(min(31, ($0 / loudest * 31).rounded())) }
        return Waveform.encode(Waveform.resample(scaled, to: 100))
    }
}

/// Records voice messages from the default microphone, like tdesktop's
/// `Media::Capture::Instance`.
nonisolated final class VoiceRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "IGram.VoiceRecorder")
    private var resampler: AVAudioConverter?
    private var encoder: OpusVoiceEncoder?

    /// Elapsed seconds and input level, safe to read from the main thread.
    var snapshot: (seconds: Double, level: Float) {
        queue.sync {
            (Double(encoder?.sampleCount ?? 0) / 48_000, encoder?.level ?? 0)
        }
    }

    func start() throws {
        let encoder = try OpusVoiceEncoder()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let resampler = AVAudioConverter(from: inputFormat, to: OpusVoiceEncoder.format) else {
            throw CocoaError(.featureUnsupported)
        }
        queue.sync {
            self.encoder = encoder
            self.resampler = resampler
        }
        // macOS 27's throwing tap API has no Swift refinement yet; its importer
        // turns the error parameter into `throws` plus a placeholder argument.
        try input.__installTap(onBus: 0, bufferSize: 4096, format: inputFormat, error: ()) { [weak self] buffer, _ in
            guard let self, let copy = Self.copy(buffer) else { return }
            self.queue.async { self.process(copy) }
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops recording and writes the voice message, or returns `nil` when too short.
    func stop() throws -> RecordedVoice? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return try queue.sync {
            guard let encoder else { return nil }
            defer { self.encoder = nil }
            let seconds = Double(encoder.sampleCount) / 48_000
            guard seconds >= 0.5 else { return nil }
            let result = encoder.finish()
            let url = try AttachmentPreparer.uploadsDirectory().appending(path: "Voice.ogg")
            try result.data.write(to: url)
            return RecordedVoice(url: url, duration: max(Int(seconds.rounded()), 1), waveform: result.waveform)
        }
    }

    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        queue.sync { encoder = nil }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let resampler, let encoder else { return }
        let ratio = OpusVoiceEncoder.format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: OpusVoiceEncoder.format, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        resampler.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, output.frameLength > 0 {
            encoder.encode(output)
        }
    }

    /// The tap reuses its buffer, so copy it before leaving the audio thread.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        if let source = buffer.floatChannelData, let target = copy.floatChannelData {
            for channel in 0..<channels {
                target[channel].update(from: source[channel], count: Int(buffer.frameLength))
            }
        } else if let source = buffer.int16ChannelData, let target = copy.int16ChannelData {
            for channel in 0..<channels {
                target[channel].update(from: source[channel], count: Int(buffer.frameLength))
            }
        } else {
            return nil
        }
        return copy
    }
}
