//
//  AudioPlayer.swift
//  IGram
//

import AVFoundation
import AppKit
import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// Plays music and voice messages one at a time, like tdesktop's
/// `Media::Player::Instance`. Files the system cannot decode are handed to
/// the default app instead.
@Observable
final class AudioPlayer {
    private(set) var currentFileId: Int?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isLoading = false

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private let delegate = Delegate()

    init() {
        delegate.onFinish = { [weak self] in self?.finish() }
    }

    var progress: Double {
        duration > 0 ? min(currentTime / duration, 1) : 0
    }

    func isCurrent(_ file: File) -> Bool { currentFileId == file.id }

    /// Plays `file`, or pauses/resumes it when it is already current.
    func toggle(_ file: File, files: FileStore, onStart: (() -> Void)? = nil) {
        if isCurrent(file), let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                progressTask?.cancel()
            } else {
                player.play()
                isPlaying = true
                trackProgress()
            }
            return
        }
        stop()
        currentFileId = file.id
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let url = try await files.downloadedURL(for: file)
                guard currentFileId == file.id else { return }
                play(url)
                onStart?()
            } catch {
                Log.ui.error("Audio download failed: \(error.telegramMessage, privacy: .public)")
                currentFileId = nil
            }
        }
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        player.currentTime = player.duration * min(max(fraction, 0), 1)
        currentTime = player.currentTime
    }

    func stop() {
        progressTask?.cancel()
        player?.stop()
        player = nil
        currentFileId = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func play(_ url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = delegate
            player.prepareToPlay()
            player.play()
            self.player = player
            duration = player.duration
            isPlaying = true
            trackProgress()
        } catch {
            Log.ui.info("AVAudioPlayer can't decode \(url.lastPathComponent, privacy: .public); opening externally")
            currentFileId = nil
            NSWorkspace.shared.open(url)
        }
    }

    private func trackProgress() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func finish() {
        progressTask?.cancel()
        isPlaying = false
        currentTime = duration
        player = nil
        currentFileId = nil
    }

    private final class Delegate: NSObject, AVAudioPlayerDelegate {
        var onFinish: (() -> Void)?

        nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            Task { @MainActor in self.onFinish?() }
        }
    }
}

/// Decodes TDLib's voice note waveform: 5-bit samples packed little-endian,
/// matching tdesktop's `documentWaveformDecode`.
enum Waveform {
    static func decode(_ data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        let count = bytes.count * 8 / 5
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let bitOffset = index * 5
            let byteIndex = bitOffset / 8
            let shift = bitOffset % 8
            var value = UInt16(bytes[byteIndex])
            if byteIndex + 1 < bytes.count {
                value |= UInt16(bytes[byteIndex + 1]) << 8
            }
            return UInt8((value >> UInt16(shift)) & 0x1F)
        }
    }

    /// Resamples to `count` bars, keeping the peak of each bucket.
    static func resample(_ samples: [UInt8], to count: Int) -> [UInt8] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: 0, count: count) }
        return (0..<count).map { bar in
            let start = bar * samples.count / count
            let end = max(start + 1, (bar + 1) * samples.count / count)
            return samples[start..<min(end, samples.count)].max() ?? 0
        }
    }
}
