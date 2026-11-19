//
//  VisualMediaView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// A photo, video or GIF tile inside a bubble.
struct VisualMediaView: View {
    let content: MessageContent
    var size: CGSize?

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @State private var isSpoilerRevealed = false

    var body: some View {
        let media = VisualMedia(content: content)
        let frame = size ?? MediaSizing.fitted(width: media.width, height: media.height)
        ZStack {
            preview(media)
            overlay(media)
        }
        .frame(width: frame.width, height: frame.height)
        .clipped()
        .contentShape(.rect)
        .onTapGesture { open(media) }
        .blur(radius: media.hasSpoiler && !isSpoilerRevealed ? 24 : 0, opaque: true)
        .overlay {
            if media.hasSpoiler, !isSpoilerRevealed {
                Image(systemName: "eye.slash.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .onTapGesture { withAnimation { isSpoilerRevealed = true } }
            }
        }
        .accessibilityLabel(Text(media.accessibilityLabel))
    }

    @ViewBuilder
    private func preview(_ media: VisualMedia) -> some View {
        let placeholder = MinithumbnailView(minithumbnail: media.minithumbnail)
        switch media.kind {
        case .animation(let file):
            let item = session.files.item(for: file)
            if let url = item.localURL {
                LoopingVideoView(url: url)
            } else {
                thumbnail(media, placeholder: placeholder)
                    .task { session.files.download(file, priority: .media) }
            }
        default:
            thumbnail(media, placeholder: placeholder)
        }
    }

    @ViewBuilder
    private func thumbnail(_ media: VisualMedia, placeholder: MinithumbnailView) -> some View {
        if let file = media.previewFile {
            FileImage(file: file, maxPixelSize: 1000, priority: .media) { placeholder }
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private func overlay(_ media: VisualMedia) -> some View {
        switch media.kind {
        case .photo(let file):
            DownloadProgressOverlay(item: session.files.item(for: file))
        case .video(let file, let duration):
            let item = session.files.item(for: file)
            ZStack {
                if item.isDownloading {
                    DownloadProgressOverlay(item: item)
                } else {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.black.opacity(0.45), in: .circle)
                }
            }
            .overlay(alignment: .topLeading) {
                MediaBadge(text: DurationFormatting.short(duration))
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        case .animation:
            MediaBadge(text: "GIF")
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func open(_ media: VisualMedia) {
        if media.hasSpoiler, !isSpoilerRevealed {
            withAnimation { isSpoilerRevealed = true }
            return
        }
        guard let file = media.fullFile else { return }
        Task {
            do {
                main.quickLookURL = try await session.files.downloadedURL(for: file)
            } catch {
                Log.ui.error("Couldn't open media: \(error.telegramMessage, privacy: .public)")
            }
        }
    }
}

/// The parts of a photo, video or animation content needed for display.
struct VisualMedia {
    enum Kind {
        case photo(File)
        case video(File, duration: Int)
        case animation(File)
    }

    let kind: Kind
    let width: Int
    let height: Int
    let minithumbnail: Minithumbnail?
    let previewFile: File?
    let fullFile: File?
    let hasSpoiler: Bool

    init(content: MessageContent) {
        switch content {
        case .messagePhoto(let value):
            let display = MediaSizing.displaySize(of: value.photo)
            let file = display?.photo
            kind = .photo(file ?? Self.emptyFile)
            width = display?.width ?? 0
            height = display?.height ?? 0
            minithumbnail = value.photo.minithumbnail
            previewFile = file
            fullFile = MediaSizing.largestSize(of: value.photo)?.photo
            hasSpoiler = value.hasSpoiler
        case .messageVideo(let value):
            kind = .video(value.video.video, duration: value.video.duration)
            width = value.video.width
            height = value.video.height
            minithumbnail = value.video.minithumbnail
            previewFile = value.video.thumbnail.flatMap(Self.imageThumbnail)
            fullFile = value.video.video
            hasSpoiler = value.hasSpoiler
        case .messageAnimation(let value):
            kind = .animation(value.animation.animation)
            width = value.animation.width
            height = value.animation.height
            minithumbnail = value.animation.minithumbnail
            previewFile = value.animation.thumbnail.flatMap(Self.imageThumbnail)
            fullFile = value.animation.animation
            hasSpoiler = value.hasSpoiler
        default:
            kind = .photo(Self.emptyFile)
            width = 0
            height = 0
            minithumbnail = nil
            previewFile = nil
            fullFile = nil
            hasSpoiler = false
        }
    }

    var accessibilityLabel: String {
        switch kind {
        case .photo: String(localized: "Photo")
        case .video: String(localized: "Video")
        case .animation: String(localized: "GIF")
        }
    }

    /// Only still-image thumbnails can be drawn by ImageIO.
    nonisolated static func imageThumbnail(_ thumbnail: Thumbnail) -> File? {
        switch thumbnail.format {
        case .thumbnailFormatJpeg, .thumbnailFormatPng, .thumbnailFormatWebp, .thumbnailFormatGif: thumbnail.file
        default: nil
        }
    }

    static let emptyFile = File(
        expectedSize: 0,
        id: 0,
        local: LocalFile(canBeDeleted: false, canBeDownloaded: false, downloadOffset: 0, downloadedPrefixSize: 0, downloadedSize: 0, isDownloadingActive: false, isDownloadingCompleted: false, path: ""),
        remote: RemoteFile(id: "", isUploadingActive: false, isUploadingCompleted: false, uniqueId: "", uploadedSize: 0),
        size: 0
    )
}

/// Circular progress while a file downloads or uploads.
struct DownloadProgressOverlay: View {
    let item: FileItem

    @Environment(TelegramSession.self) private var session

    var body: some View {
        if item.isDownloading || item.isUploading {
            ZStack {
                Circle().fill(.black.opacity(0.45))
                Circle()
                    .trim(from: 0, to: max(item.progress, 0.03))
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(6)
                    .animation(.linear, value: item.progress)
                Image(systemName: "xmark")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            .onTapGesture { session.files.cancelDownload(item.file) }
        }
    }
}

/// Small dark label over media, such as a duration.
struct MediaBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.5), in: .capsule)
    }
}
