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
    /// Stretches the bubble to the row's width, so it lines up with the bot
    /// keyboard attached below it.
    var fillsWidth = false

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.chatThemeStyle) private var theme

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
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            content
            if let reactions {
                ReactionsView(message: entry.captionMessage, reactions: reactions, isOutgoingStyle: isOutgoingStyle)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 7)
            }
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .foregroundStyle(theme.primaryText(outgoing: isOutgoingStyle))
        .background(theme.bubbleStyle(outgoing: isOutgoingStyle), in: shape)
        .clipShape(shape)
        .background(alignment: isOutgoingStyle ? .bottomTrailing : .bottomLeading) {
            if showsTail {
                BubbleTail()
                    .fill(theme.bubbleStyle(outgoing: isOutgoingStyle))
                    .frame(width: BubbleTail.size.width, height: BubbleTail.size.height)
                    .scaleEffect(x: isOutgoingStyle ? 1 : -1)
                    .offset(x: isOutgoingStyle ? BubbleTail.overhang : -BubbleTail.overhang)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Messages draws a tail on the last bubble of a run; media fills its
    /// rounded rectangle without one.
    private var showsTail: Bool {
        guard theme.isSystem, entry.isLastInGroup else { return false }
        switch message.content {
        case .messagePhoto, .messageVideo, .messageAnimation:
            return !(entry.captionMessage.text?.text.isEmpty ?? true)
        default:
            return true
        }
    }

    // MARK: - Standalone content

    /// Stickers, big emoji and round videos are drawn without a bubble.
    private var isStandalone: Bool {
        switch message.content {
        case .messageSticker, .messageAnimatedEmoji, .messageDice, .messageVideoNote: true
        case .messageText: jumboEmojiCount != nil
        default: false
        }
    }

    /// One to three emoji sent on their own show large and without a bubble,
    /// as in Messages and Telegram.
    private var jumboEmojiCount: Int? {
        guard case .messageText(let value) = message.content, value.linkPreview == nil,
              value.text.entities.isEmpty else { return nil }
        return JumboEmoji.count(in: value.text.text)
    }

    private var standaloneBody: some View {
        VStack(alignment: isOutgoingStyle ? .trailing : .leading, spacing: 4) {
            if hasHeader {
                VStack(alignment: .leading, spacing: 4) { headers }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(theme.primaryText(outgoing: isOutgoingStyle))
                    .background(theme.bubbleStyle(outgoing: isOutgoingStyle), in: .rect(cornerRadius: 10))
                    .frame(maxWidth: 300, alignment: .leading)
            }
            standaloneContent
                .overlay(alignment: .bottomTrailing) {
                    MessageFooter(message: message, chat: chat, isOutgoingStyle: isOutgoingStyle, overMedia: true)
                }
            if let reactions {
                ReactionsView(message: message, reactions: reactions, isOutgoingStyle: isOutgoingStyle)
                    .frame(maxWidth: 240, alignment: isOutgoingStyle ? .trailing : .leading)
            }
        }
    }

    /// Reactions of the message carrying the caption (albums react as a whole).
    private var reactions: [MessageReaction]? {
        guard let list = entry.captionMessage.interactionInfo?.reactions?.reactions, !list.isEmpty else { return nil }
        return list
    }

    @ViewBuilder
    private var standaloneContent: some View {
        switch message.content {
        case .messageSticker(let value):
            StickerView(sticker: value.sticker)
                .contentShape(.rect)
                .onTapGesture {
                    if value.sticker.setId.rawValue != 0 {
                        main.stickerSet = .id(value.sticker.setId)
                    }
                }
        case .messageAnimatedEmoji(let value):
            if let sticker = value.animatedEmoji.sticker {
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
        case .messageText(let value):
            Text(value.text.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: JumboEmoji.pointSize(forCount: jumboEmojiCount ?? 1)))
                .padding(.bottom, 18)
                .padding(.horizontal, 2)
        default:
            EmptyView()
        }
    }

    // MARK: - Headers

    /// The sender's name above the content: inside the bubble for tdesktop
    /// styles; the system style shows it above the bubble instead.
    private var showsSenderName: Bool {
        !theme.isSystem && Self.showsSenderName(entry: entry, chat: chat)
    }

    static func showsSenderName(entry: MessageEntry, chat: ChatItem) -> Bool {
        let message = entry.primary
        return entry.isFirstInGroup && !message.isOutgoing
            && (chat.isGroup || (chat.isChannel && message.senderId.chatId != chat.id))
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
            if let preview = value.linkPreview {
                linkPreviewBlock(text: value.text, preview: preview)
            } else {
                textBlock(value.text)
            }
        case .messagePhoto, .messageVideo, .messageAnimation:
            mediaBlock
        case .messageDocument(let value):
            paddedBlock(caption: value.caption) {
                DocumentView(document: value.document, isOutgoingStyle: isOutgoingStyle)
            }
        case .messageAudio(let value):
            paddedBlock(caption: value.caption) {
                AudioView(audio: value.audio, isOutgoingStyle: isOutgoingStyle)
            }
        case .messageVoiceNote(let value):
            paddedBlock(caption: value.caption) {
                VoiceNoteView(message: message, voiceNote: value.voiceNote, isListened: value.isListened, isOutgoingStyle: isOutgoingStyle)
            }
        case .messageLocation(let value):
            paddedBlock { LocationView(location: value.location) }
        case .messageLiveLocation(let value):
            paddedBlock { LocationView(location: value.location.location) }
        case .messageVenue(let value):
            paddedBlock { LocationView(location: value.venue.location, venue: value.venue) }
        case .messageContact(let value):
            paddedBlock { ContactView(contact: value.contact, isOutgoingStyle: isOutgoingStyle) }
        case .messagePoll(let value):
            paddedBlock { PollView(message: message, poll: value.poll, isOutgoingStyle: isOutgoingStyle) }
        case .messageCall(let value):
            paddedBlock { CallView(call: value, isOutgoing: message.isOutgoing, isOutgoingStyle: isOutgoingStyle) }
        case .messageStory(let value):
            paddedBlock {
                Button {
                    main.openStory(posterChatId: value.storyPosterChatId, storyId: value.storyId)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(theme.accent(outgoing: isOutgoingStyle))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(value.viaMention ? String(localized: "Mentioned you in a story") : String(localized: "Story"))
                                .font(.callout.weight(.semibold))
                            Text(session.chats.chat(value.storyPosterChatId).map { session.title(of: $0) } ?? String(localized: "Tap to view"))
                                .font(.caption)
                                .foregroundStyle(theme.secondary(outgoing: isOutgoingStyle))
                        }
                    }
                    .frame(minWidth: 160, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        default:
            fallbackBlock
        }
    }

    /// Non-media attachments: padded content, then the caption or a footer line.
    private func paddedBlock<Content: View>(
        caption: FormattedText? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
                .padding(.horizontal, 12)
                .padding(.top, hasHeader ? 0 : 8)
            if let caption, !caption.text.isEmpty {
                textBlock(caption)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    MessageFooter(message: entry.captionMessage, chat: chat, isOutgoingStyle: isOutgoingStyle)
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 6)
            }
        }
    }

    /// Photos, videos and GIFs fill the bubble; the caption sits below.
    @ViewBuilder
    private var mediaBlock: some View {
        let caption = entry.captionMessage.text ?? FormattedText(entities: [], text: "")
        // The media decides the bubble's width; a caption wraps inside it.
        FirstChildWidthStack(spacing: 5) {
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
    }

    /// Text followed by its web page preview; the footer moves below the card.
    private func linkPreviewBlock(text: FormattedText, preview: LinkPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if preview.showAboveText {
                LinkPreviewView(preview: preview, isOutgoingStyle: isOutgoingStyle)
                    .padding(.horizontal, 12)
                    .padding(.top, hasHeader ? 0 : 8)
            }
            if !text.text.isEmpty {
                Text(text.attributedString(linkColor: theme.accent(outgoing: isOutgoingStyle)))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, hasHeader || preview.showAboveText ? 0 : 7)
            }
            if !preview.showAboveText {
                LinkPreviewView(preview: preview, isOutgoingStyle: isOutgoingStyle)
                    .padding(.horizontal, 12)
            }
            HStack {
                Spacer(minLength: 0)
                MessageFooter(message: entry.captionMessage, chat: chat, isOutgoingStyle: isOutgoingStyle)
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 6)
        }
    }

    /// Text with the footer tucked into the end of the last line.
    func textBlock(_ text: FormattedText) -> some View {
        let footerMessage = entry.captionMessage
        let placeholder = Text(MessageFooter.placeholder(
            for: footerMessage,
            chat: chat,
            isDeleted: session.archive.isDeleted(chatId: footerMessage.chatId, messageId: footerMessage.id),
            seconds: ExtraFeatures.shared.showSeconds
        ))
            .font(.caption2)
            .foregroundStyle(.clear)
        return Text("\(Text(text.attributedString(linkColor: theme.accent(outgoing: isOutgoingStyle))))\(placeholder)")
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 24, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, hasHeader ? 0 : 7)
            .padding(.bottom, 7)
            .overlay(alignment: .bottomTrailing) {
                MessageFooter(message: entry.captionMessage, chat: chat, isOutgoingStyle: isOutgoingStyle)
                    .padding(.trailing, 11)
                    .padding(.bottom, 6)
            }
    }

    /// Content types without a dedicated view yet show their preview text.
    private var fallbackBlock: some View {
        let preview = session.formatter(history: history).preview(message.content)
        return textBlock(FormattedText(entities: [TextEntity(length: preview.utf16.count, offset: 0, type: .textEntityTypeItalic)], text: preview))
    }

    // MARK: - Shape

    private var shape: AnyShape {
        if theme.isSystem {
            return AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        let large: CGFloat = 14
        let small: CGFloat = 5
        if isOutgoingStyle {
            return AnyShape(UnevenRoundedRectangle(
                topLeadingRadius: large,
                bottomLeadingRadius: large,
                bottomTrailingRadius: entry.isLastInGroup ? large : small,
                topTrailingRadius: entry.isFirstInGroup ? large : small
            ))
        }
        return AnyShape(UnevenRoundedRectangle(
            topLeadingRadius: entry.isFirstInGroup ? large : small,
            bottomLeadingRadius: entry.isLastInGroup ? large : small,
            bottomTrailingRadius: large,
            topTrailingRadius: large
        ))
    }
}

/// The curled tail of a Messages bubble, drawn for an outgoing bubble (the
/// bubble's trailing edge is `overhang` points from the right) and mirrored for
/// incoming ones.
struct BubbleTail: Shape {
    static let size = CGSize(width: 22, height: 20)
    static let overhang: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let edge = w - Self.overhang
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: edge, y: 0))
        path.addLine(to: CGPoint(x: edge, y: h * 0.25))
        path.addCurve(
            to: CGPoint(x: w, y: h),
            control1: CGPoint(x: edge, y: h * 0.72),
            control2: CGPoint(x: edge + 2.5, y: h * 0.94)
        )
        path.addCurve(
            to: CGPoint(x: w - 9, y: h - 1.8),
            control1: CGPoint(x: w - 2.5, y: h + 0.2),
            control2: CGPoint(x: w - 5.5, y: h - 0.9)
        )
        path.addCurve(
            to: CGPoint(x: w - 16, y: h),
            control1: CGPoint(x: w - 11.5, y: h - 0.4),
            control2: CGPoint(x: w - 13.5, y: h)
        )
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// A vertical stack as wide as its first child (up to the offered width);
/// later children wrap to that width, e.g. a caption under a photo.
struct FirstChildWidthStack: Layout {
    var spacing: CGFloat = 0

    struct Cache {
        var idealWidth: CGFloat?
        var heights: [CGFloat: [CGFloat]] = [:]
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = width(for: proposal, subviews: subviews, cache: &cache)
        let heights = heights(at: width, subviews: subviews, cache: &cache)
        let total = heights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let heights = heights(at: bounds.width, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for (subview, height) in zip(subviews, heights) {
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }

    private func width(for proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat {
        guard let first = subviews.first else { return 0 }
        let ideal = cache.idealWidth ?? first.sizeThatFits(.unspecified).width
        cache.idealWidth = ideal
        guard let offered = proposal.width, offered >= 1 else { return ideal }
        return min(ideal, offered)
    }

    private func heights(at width: CGFloat, subviews: Subviews, cache: inout Cache) -> [CGFloat] {
        let key = width.rounded()
        if let heights = cache.heights[key] { return heights }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        cache.heights[key] = heights
        return heights
    }
}

/// Detects messages that are only a few emoji, shown large like Messages does.
nonisolated enum JumboEmoji {
    static let maximumCount = 3

    /// The number of emoji when `text` is one to three emoji (spaces aside),
    /// otherwise `nil`.
    static func count(in text: String) -> Int? {
        var count = 0
        for character in text where !character.isWhitespace {
            guard isEmoji(character) else { return nil }
            count += 1
            if count > maximumCount { return nil }
        }
        return count > 0 ? count : nil
    }

    /// Emoji presentation by default, or an emoji sequence (variation
    /// selector, keycap, skin tone, ZWJ). Digits and © alone are text.
    static func isEmoji(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        return first.properties.isEmoji && character.unicodeScalars.count > 1
    }

    static func pointSize(forCount count: Int) -> CGFloat {
        switch count {
        case 1: 64
        case 2: 52
        default: 44
        }
    }
}
