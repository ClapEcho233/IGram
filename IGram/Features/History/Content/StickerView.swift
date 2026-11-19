//
//  StickerView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// A sticker drawn without a bubble. Static WebP stickers render directly;
/// animated (TGS) and video (WebM) stickers fall back to their still thumbnail.
struct StickerView: View {
    let sticker: Sticker
    var side: CGFloat = 180

    var body: some View {
        let size = MediaSizing.fitted(
            width: sticker.width,
            height: sticker.height,
            maximum: CGSize(width: side, height: side),
            minSide: side / 2
        )
        Group {
            switch sticker.format {
            case .stickerFormatWebp:
                FileImage(file: sticker.sticker, maxPixelSize: Int(side * 2), priority: .media, contentMode: .fit) {
                    thumbnail
                }
            case .stickerFormatTgs, .stickerFormatWebm:
                thumbnail
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel(Text("\(sticker.emoji) Sticker"))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnail = sticker.thumbnail, let file = VisualMedia.imageThumbnail(thumbnail) {
            FileImage(file: file, maxPixelSize: Int(side * 2), priority: .media, contentMode: .fit) {
                EmojiPlaceholder(emoji: sticker.emoji, size: side * 0.5)
            }
        } else {
            EmojiPlaceholder(emoji: sticker.emoji, size: side * 0.5)
        }
    }
}

/// A large emoji, for animated emoji and stickers without a drawable file.
struct EmojiPlaceholder: View {
    let emoji: String
    var size: CGFloat = 72

    var body: some View {
        Text(emoji.isEmpty ? "🙂" : emoji)
            .font(.system(size: size))
    }
}

/// A round video message, like tdesktop's `HistoryView::Gif` in round mode.
struct VideoNoteView: View {
    let videoNote: VideoNote
    var diameter: CGFloat = 200

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main

    var body: some View {
        let item = session.files.item(for: videoNote.video)
        ZStack {
            if let url = item.localURL {
                LoopingVideoView(url: url)
            } else {
                Group {
                    if let thumbnail = videoNote.thumbnail, let file = VisualMedia.imageThumbnail(thumbnail) {
                        FileImage(file: file, maxPixelSize: Int(diameter * 2)) {
                            MinithumbnailView(minithumbnail: videoNote.minithumbnail)
                        }
                    } else {
                        MinithumbnailView(minithumbnail: videoNote.minithumbnail)
                    }
                }
                .task { session.files.download(videoNote.video, priority: .media) }
                DownloadProgressOverlay(item: item)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(.circle)
        .overlay(alignment: .bottomLeading) {
            MediaBadge(text: DurationFormatting.short(videoNote.duration))
                .padding(.leading, 18)
                .padding(.bottom, 10)
        }
        .contentShape(.circle)
        .onTapGesture {
            Task {
                do {
                    main.quickLookURL = try await session.files.downloadedURL(for: videoNote.video)
                } catch {
                    Log.ui.error("Couldn't open video message: \(error.telegramMessage, privacy: .public)")
                }
            }
        }
        .accessibilityLabel(Text("Video message"))
    }
}
