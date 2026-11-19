//
//  FileContentViews.swift
//  IGram
//

import AppKit
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// A document attachment, after tdesktop's `HistoryView::Document`.
struct DocumentView: View {
    let document: TDLibKit.Document
    let isOutgoingStyle: Bool

    @Environment(TelegramSession.self) private var session
    @Environment(\.chatThemeStyle) private var theme

    var body: some View {
        let item = session.files.item(for: document.document)
        HStack(spacing: 10) {
            FileStateButton(item: item, tint: Self.tint(for: document.fileName)) {
                if let thumbnail = document.thumbnail, let file = VisualMedia.imageThumbnail(thumbnail) {
                    FileImage(file: file, maxPixelSize: 120, priority: .thumbnail) {
                        Self.tint(for: document.fileName)
                    }
                } else {
                    Text(Self.extensionLabel(document.fileName))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            } open: {
                open(item)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(document.fileName.isEmpty ? String(localized: "File") : document.fileName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sizeText(item))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondary(outgoing: isOutgoingStyle))
            }
            .frame(minWidth: 140, alignment: .leading)
        }
    }

    private func sizeText(_ item: FileItem) -> String {
        let total = DurationFormatting.fileSize(item.totalSize)
        if item.isDownloading {
            return "\(DurationFormatting.fileSize(item.file.local.downloadedSize)) / \(total)"
        }
        if item.isUploading {
            return "\(DurationFormatting.fileSize(item.file.remote.uploadedSize)) / \(total)"
        }
        return total
    }

    private func open(_ item: FileItem) {
        guard let url = item.localURL else { return }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func extensionLabel(_ fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension
        return ext.isEmpty ? "FILE" : String(ext.prefix(4)).uppercased()
    }

    /// File-type colors like tdesktop's document icons.
    static func tint(for fileName: String) -> Color {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pdf", "ppt", "pptx", "key": Color(red: 0.89, green: 0.33, blue: 0.33)
        case "xls", "xlsx", "csv", "numbers": Color(red: 0.32, green: 0.72, blue: 0.29)
        case "zip", "rar", "7z", "tar", "gz", "dmg": Color(red: 0.95, green: 0.6, blue: 0.24)
        case "doc", "docx", "txt", "rtf", "pages", "md": Color(red: 0.2, green: 0.53, blue: 0.92)
        default: Color(red: 0.45, green: 0.55, blue: 0.65)
        }
    }
}

/// The round button of file attachments: download, progress with cancel,
/// or the file icon once it is local.
struct FileStateButton<Icon: View>: View {
    let item: FileItem
    var tint: Color = .accentColor
    @ViewBuilder var icon: Icon
    let open: () -> Void

    @Environment(TelegramSession.self) private var session

    var body: some View {
        Button {
            if item.isDownloaded {
                open()
            } else if item.isDownloading {
                session.files.cancelDownload(item.file)
            } else {
                session.files.download(item.file, priority: .userInitiated)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(tint)
                icon
                if !item.isDownloaded {
                    Color.black.opacity(0.3)
                    if item.isDownloading || item.isUploading {
                        Circle()
                            .trim(from: 0, to: max(item.progress, 0.03))
                            .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(8)
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                    } else {
                        Image(systemName: "arrow.down").font(.callout.weight(.bold)).foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(item.isDownloaded ? "Open" : item.isDownloading ? "Cancel download" : "Download")
    }
}

/// A music file with play controls.
struct AudioView: View {
    let audio: Audio
    let isOutgoingStyle: Bool

    @Environment(TelegramSession.self) private var session
    @Environment(AudioPlayer.self) private var player
    @Environment(\.chatThemeStyle) private var theme

    var body: some View {
        let isCurrent = player.isCurrent(audio.audio)
        HStack(spacing: 10) {
            PlayButton(isPlaying: isCurrent && player.isPlaying, isLoading: isCurrent && player.isLoading, isOutgoingStyle: isOutgoingStyle) {
                player.toggle(audio.audio, files: session.files)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(audio.title.isEmpty ? audio.fileName : audio.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if isCurrent, player.duration > 0 {
                    ProgressView(value: player.progress)
                        .progressViewStyle(.linear)
                        .tint(theme.accent(outgoing: isOutgoingStyle))
                } else {
                    Text(audio.performer.isEmpty ? DurationFormatting.short(audio.duration) : "\(audio.performer) · \(DurationFormatting.short(audio.duration))")
                        .font(.caption)
                        .foregroundStyle(theme.secondary(outgoing: isOutgoingStyle))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 160, alignment: .leading)
        }
    }
}

/// A voice message with its waveform, after tdesktop's voice document layout.
struct VoiceNoteView: View {
    let message: ChatMessage
    let voiceNote: VoiceNote
    let isListened: Bool
    let isOutgoingStyle: Bool

    @Environment(TelegramSession.self) private var session
    @Environment(AudioPlayer.self) private var player
    @Environment(\.chatThemeStyle) private var theme

    private static let barCount = 48

    var body: some View {
        let isCurrent = player.isCurrent(voiceNote.voice)
        let bars = Waveform.resample(Waveform.decode(voiceNote.waveform), to: Self.barCount)
        HStack(spacing: 10) {
            PlayButton(isPlaying: isCurrent && player.isPlaying, isLoading: isCurrent && player.isLoading, isOutgoingStyle: isOutgoingStyle) {
                let chatId = message.chatId
                let messageId = message.id
                let api = session.api
                player.toggle(voiceNote.voice, files: session.files) {
                    Task { _ = try? await api.openMessageContent(chatId: chatId, messageId: messageId) }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                WaveformView(bars: bars, progress: isCurrent ? player.progress : 0, isOutgoingStyle: isOutgoingStyle)
                    .frame(width: CGFloat(Self.barCount) * 3.5, height: 22)
                HStack(spacing: 4) {
                    Text(isCurrent && player.currentTime > 0 ? DurationFormatting.short(Int(player.currentTime)) : DurationFormatting.short(voiceNote.duration))
                    if !isListened, !message.isOutgoing {
                        Circle().fill(theme.accent(outgoing: isOutgoingStyle)).frame(width: 5, height: 5)
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondary(outgoing: isOutgoingStyle))
            }
        }
        .accessibilityLabel(Text("Voice message, \(DurationFormatting.short(voiceNote.duration))"))
    }
}

struct WaveformView: View {
    let bars: [UInt8]
    let progress: Double
    let isOutgoingStyle: Bool

    @Environment(\.chatThemeStyle) private var theme

    var body: some View {
        Canvas { context, size in
            guard !bars.isEmpty else { return }
            let step = size.width / CGFloat(bars.count)
            let barWidth = max(step - 1.5, 1)
            for (index, value) in bars.enumerated() {
                let height = max(CGFloat(value) / 31 * size.height, 2)
                let rect = CGRect(x: CGFloat(index) * step, y: size.height - height, width: barWidth, height: height)
                let played = Double(index) / Double(bars.count) < progress
                let color = played ? theme.accent(outgoing: isOutgoingStyle) : theme.secondary(outgoing: isOutgoingStyle).opacity(0.6)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
            }
        }
    }
}

struct PlayButton: View {
    let isPlaying: Bool
    var isLoading = false
    let isOutgoingStyle: Bool
    let action: () -> Void

    @Environment(\.chatThemeStyle) private var theme

    private var iconColor: Color {
        let accentRGB = isOutgoingStyle ? theme.palette.outgoingAccent : theme.palette.incomingAccent
        return ChatThemePalette.isDarkColor(accentRGB)
            ? .white
            : Color(rgb: theme.palette.outgoingBubble.representativeRGB)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(theme.accent(outgoing: isOutgoingStyle))
                if isLoading {
                    ProgressView().controlSize(.small).tint(iconColor)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(iconColor)
                        .offset(x: isPlaying ? 0 : 1.5)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "Pause" : "Play")
    }
}
