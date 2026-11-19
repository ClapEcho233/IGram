//
//  MessageBubble.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// A message bubble: sender name, forward and reply headers, content and footer.
///
/// Mirrors the parts tdesktop's `HistoryView::Message::draw` paints.
struct MessageBubble: View {
    let entry: MessageEntry
    let chat: ChatItem
    let history: HistoryModel

    @Environment(TelegramSession.self) private var session

    private var message: ChatMessage { entry.primary }
    private var isOutgoingStyle: Bool { message.isOutgoing && !chat.isChannel }

    var body: some View {
        if isStandalone {
            standaloneBody
        } else {
            bubbleBody
        }
    }

    private var bubbleBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            if hasHeader {
                headers
                    .padding(.horizontal, 10)
                    .padding(.top, 7)
            }
            content
        }
        .background(ChatTheme.bubble(outgoing: isOutgoingStyle), in: shape)
        .clipShape(shape)
        .frame(maxWidth: 520, alignment: isOutgoingStyle ? .trailing : .leading)
    }

    // MARK: - Standalone content

    /// Stickers, big emoji and round videos are drawn without a bubble.
    private var isStandalone: Bool {
        switch message.content {
        case .messageSticker, .messageAnimatedEmoji, .messageDice, .messageVideoNote: true
        default: false
        }
    }

    private var standaloneBody: some View {
        VStack(alignment: isOutgoingStyle ? .trailing : .leading, spacing: 4) {
            if hasHeader {
                VStack(alignment: .leading, spacing: 4) { headers }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ChatTheme.bubble(outgoing: isOutgoingStyle), in: .rect(cornerRadius: 10))
                    .frame(maxWidth: 300, alignment: .leading)
            }
            standaloneContent
                .overlay(alignment: .bottomTrailing) {
                    MessageFooter(message: message, chat: chat, isOutgoingStyle: isOutgoingStyle, overMedia: true)
                }
        }
    }

    @ViewBuilder
    private var standaloneContent: some View {
        switch message.content {
        case .messageSticker(let value):
            StickerView(sticker: value.sticker)
        case .messageAnimatedEmoji(let value):
            if let sticker = value.animatedEmoji.sticker, sticker.format == .stickerFormatWebp {
                StickerView(sticker: sticker, side: 120)
            } else {
                EmojiPlaceholder(emoji: value.emoji, size: 80)
                    .padding(.bottom, 14)
            }
        case .messageDice(let value):
            VStack(spacing: 2) {
                EmojiPlaceholder(emoji: value.emoji, size: 64)
                if value.value > 0 {
                    Text("Result: \(value.value)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 18)
        case .messageVideoNote(let value):
            VideoNoteView(videoNote: value.videoNote)
        default:
            EmptyView()
        }
    }

    // MARK: - Headers

    private var showsSenderName: Bool {
        entry.isFirstInGroup && !message.isOutgoing && (chat.isGroup || (chat.isChannel && message.senderId.chatId != chat.id))
    }

    private var hasHeader: Bool {
        showsSenderName || message.forwardInfo != nil || message.replyTo != nil
    }

    @ViewBuilder
    private var headers: some View {
        if showsSenderName {
            HStack(spacing: 4) {
                Text(session.displayName(message.senderId))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PeerColor.name(session.accentColorId(of: message.senderId)))
                    .lineLimit(1)
                if !message.authorSignature.isEmpty, message.senderId.chatId != nil {
                    Text(message.authorSignature)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if let forward = message.forwardInfo {
            ForwardHeader(info: forward, isOutgoingStyle: isOutgoingStyle)
        }
        if message.replyTo != nil {
            ReplyHeader(message: message, history: history, isOutgoingStyle: isOutgoingStyle)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch message.content {
        case .messageText(let value):
            textBlock(value.text)
        case .messagePhoto, .messageVideo, .messageAnimation:
            mediaBlock
        default:
            fallbackBlock
        }
    }

    /// Photos, videos and GIFs fill the bubble; the caption sits below.
    @ViewBuilder
    private var mediaBlock: some View {
        let caption = entry.captionMessage.text ?? FormattedText(entities: [], text: "")
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if entry.isAlbum {
                    AlbumView(messages: entry.messages)
                } else {
                    VisualMediaView(content: message.content)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if caption.text.isEmpty {
                    MessageFooter(message: entry.captionMessage, chat: chat, isOutgoingStyle: isOutgoingStyle, overMedia: true)
                        .padding(6)
                }
            }
            if !caption.text.isEmpty {
                textBlock(caption)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Text with the footer tucked into the end of the last line.
    func textBlock(_ text: FormattedText) -> some View {
        let placeholder = Text(MessageFooter.placeholder(for: entry.captionMessage, chat: chat))
            .font(.caption2)
            .foregroundStyle(.clear)
        return Text("\(Text(text.attributedString(linkColor: ChatTheme.accent(outgoing: isOutgoingStyle))))\(placeholder)")
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 40, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, hasHeader ? 0 : 7)
            .padding(.bottom, 7)
            .overlay(alignment: .bottomTrailing) {
                MessageFooter(message: entry.captionMessage, chat: chat, isOutgoingStyle: isOutgoingStyle)
                    .padding(.trailing, 9)
                    .padding(.bottom, 6)
            }
    }

    /// Content types without a dedicated view yet show their preview text.
    private var fallbackBlock: some View {
        let preview = session.formatter(history: history).preview(message.content)
        return textBlock(FormattedText(entities: [TextEntity(length: preview.utf16.count, offset: 0, type: .textEntityTypeItalic)], text: preview))
    }

    // MARK: - Shape

    private var shape: UnevenRoundedRectangle {
        let large: CGFloat = 14
        let small: CGFloat = 5
        if isOutgoingStyle {
            return UnevenRoundedRectangle(
                topLeadingRadius: large,
                bottomLeadingRadius: large,
                bottomTrailingRadius: entry.isLastInGroup ? large : small,
                topTrailingRadius: entry.isFirstInGroup ? large : small
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: entry.isFirstInGroup ? large : small,
            bottomLeadingRadius: entry.isLastInGroup ? large : small,
            bottomTrailingRadius: large,
            topTrailingRadius: large
        )
    }
}
