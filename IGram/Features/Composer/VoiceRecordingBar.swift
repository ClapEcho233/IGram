//
//  VoiceRecordingBar.swift
//  IGram
//

import AVFAudio
import Observation
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Drives a voice recording from the composer, like tdesktop's
/// `HistoryView::Controls::VoiceRecordBar`.
@Observable
final class VoiceRecordingModel {
    private(set) var isRecording = false
    private(set) var seconds: Double = 0
    private(set) var level: Float = 0

    @ObservationIgnored private var recorder: VoiceRecorder?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Starts recording; returns an error message when it can't.
    func start(chatId: Int64, api: TDLibClient) async -> String? {
        guard !isRecording else { return nil }
        guard await AVAudioApplication.requestRecordPermission() else {
            return String(localized: "IGram doesn't have access to the microphone. Allow it in System Settings → Privacy & Security → Microphone.")
        }
        let recorder = VoiceRecorder()
        do {
            try recorder.start()
        } catch {
            Log.ui.error("Recording failed to start: \(error.localizedDescription, privacy: .public)")
            return String(localized: "Couldn't start recording.")
        }
        self.recorder = recorder
        isRecording = true
        seconds = 0
        ticker = Task { [weak self] in
            var lastAction = Date.distantPast
            while !Task.isCancelled {
                guard let self, let recorder = self.recorder else { return }
                let snapshot = recorder.snapshot
                self.seconds = snapshot.seconds
                self.level = snapshot.level
                if Date.now.timeIntervalSince(lastAction) > 5 {
                    lastAction = .now
                    _ = try? await api.sendChatAction(action: .chatActionRecordingVoiceNote, businessConnectionId: nil, chatId: chatId, topicId: nil)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return nil
    }

    /// Stops recording and returns the voice message, or `nil` if it was too short.
    func finish() -> RecordedVoice? {
        defer { reset() }
        do {
            return try recorder?.stop()
        } catch {
            Log.ui.error("Saving the recording failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func cancel() {
        recorder?.cancel()
        reset()
    }

    private func reset() {
        ticker?.cancel()
        ticker = nil
        recorder = nil
        isRecording = false
        level = 0
    }
}

/// Shown in place of the text field while recording.
struct VoiceRecordingBar: View {
    let model: VoiceRecordingModel
    let onCancel: () -> Void

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(isPulsing ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.6).repeatForever(), value: isPulsing)
                .onAppear { isPulsing = true }
            Text(Self.format(model.seconds))
                .font(.body.monospacedDigit())
            GeometryReader { proxy in
                Capsule()
                    .fill(.red.opacity(0.25))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.red.opacity(0.7))
                            .frame(width: max(proxy.size.width * CGFloat(model.level), 4))
                            .animation(.linear(duration: 0.1), value: model.level)
                    }
            }
            .frame(height: 6)
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .frame(minHeight: 30)
    }

    /// `0:05,3` like tdesktop's recording timer.
    static func format(_ seconds: Double) -> String {
        let whole = Int(seconds)
        let tenths = Int((seconds - Double(whole)) * 10)
        return "\(DurationFormatting.short(whole)),\(tenths)"
    }
}
