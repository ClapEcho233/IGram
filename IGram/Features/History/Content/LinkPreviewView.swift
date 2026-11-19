//
//  LinkPreviewView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// A web page preview under a text message, after tdesktop's `HistoryView::WebPage`.
struct LinkPreviewView: View {
    let preview: LinkPreview
    let isOutgoingStyle: Bool

    @Environment(\.openURL) private var openURL
    @Environment(\.chatThemeStyle) private var theme

    var body: some View {
        let accent = theme.accent(outgoing: isOutgoingStyle)
        let media = LinkPreviewMedia(type: preview.type)
        let largeMedia = preview.showLargeMedia && media.isLarge
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !preview.siteName.isEmpty {
                            Text(preview.siteName)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(accent)
                                .lineLimit(1)
                        }
                        if !preview.title.isEmpty {
                            Text(preview.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(2)
                        }
                        if !preview.description.text.isEmpty {
                            Text(preview.description.attributedString(linkColor: accent))
                                .font(.callout)
                                .lineLimit(largeMedia ? 3 : 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !largeMedia, let file = media.thumbnailFile {
                        FileImage(file: file, maxPixelSize: 160, priority: .thumbnail) {
                            MinithumbnailView(minithumbnail: media.minithumbnail)
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(.rect(cornerRadius: 6))
                    }
                }
                if largeMedia, let file = media.largeFile {
                    let size = MediaSizing.fitted(width: media.width, height: media.height, maximum: CGSize(width: 320, height: 240))
                    FileImage(file: file, maxPixelSize: 900) {
                        MinithumbnailView(minithumbnail: media.minithumbnail)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay {
                        if media.isVideo {
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.45), in: .circle)
                        }
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 4)
            .padding(.trailing, 6)
        }
        .background(accent.opacity(0.08), in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onTapGesture {
            if let url = FormattedText.webURL(from: preview.url) { openURL(url) }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .help(preview.url)
    }
}

/// The picture a link preview carries, whatever its type.
struct LinkPreviewMedia {
    var thumbnailFile: File?
    var largeFile: File?
    var minithumbnail: Minithumbnail?
    var width = 0
    var height = 0
    var isVideo = false

    var isLarge: Bool { largeFile != nil }

    init(type: LinkPreviewType) {
        switch type {
        case .linkPreviewTypeArticle(let value):
            if let photo = value.photo { use(photo) }
        case .linkPreviewTypePhoto(let value):
            use(value.photo)
        case .linkPreviewTypeVideo(let value):
            if let cover = value.cover {
                use(cover)
            } else if let thumbnail = value.video.thumbnail.flatMap({ VisualMedia.imageThumbnail($0) }) {
                thumbnailFile = thumbnail
                largeFile = thumbnail
                width = value.video.width
                height = value.video.height
            }
            minithumbnail = minithumbnail ?? value.video.minithumbnail
            isVideo = true
        case .linkPreviewTypeEmbeddedVideoPlayer(let value):
            if let photo = value.thumbnail { use(photo) }
            isVideo = true
        case .linkPreviewTypeAnimation(let value):
            thumbnailFile = value.animation.thumbnail.flatMap { VisualMedia.imageThumbnail($0) }
            largeFile = thumbnailFile
            minithumbnail = value.animation.minithumbnail
            width = value.animation.width
            height = value.animation.height
        case .linkPreviewTypeChat(let value):
            useSmall(value.photo)
        case .linkPreviewTypeUser(let value):
            useSmall(value.photo)
        case .linkPreviewTypeChannelBoost(let value):
            useSmall(value.photo)
        case .linkPreviewTypeSticker(let value):
            thumbnailFile = value.sticker.format == .stickerFormatWebp ? value.sticker.sticker : value.sticker.thumbnail.flatMap { VisualMedia.imageThumbnail($0) }
        default:
            break
        }
    }

    private mutating func use(_ photo: Photo) {
        thumbnailFile = photo.sizes.first { max($0.width, $0.height) >= 160 }?.photo ?? photo.sizes.last?.photo
        let display = MediaSizing.displaySize(of: photo)
        largeFile = display?.photo
        width = display?.width ?? 0
        height = display?.height ?? 0
        minithumbnail = photo.minithumbnail
    }

    /// Profile pictures stay small even when the preview asks for large media.
    private mutating func useSmall(_ photo: ChatPhoto?) {
        guard let photo else { return }
        thumbnailFile = photo.sizes.first { max($0.width, $0.height) >= 160 }?.photo ?? photo.sizes.last?.photo
        minithumbnail = photo.minithumbnail
    }
}
