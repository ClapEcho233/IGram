//
//  MessageRow.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// One history entry: a day header, the unread bar or a message.
struct HistoryEntryView: View {
    let entry: HistoryEntry
    let chat: ChatItem
    let history: HistoryModel
    var highlightedMessageId: Int64?

    var body: some View {
        switch entry {
        case .day(let date):
            DayHeader(date: date)
        case .unread:
            UnreadSeparator()
        case .message(let messageEntry):
            MessageRow(
                entry: messageEntry,
                chat: chat,
                history: history,
                isHighlighted: highlightedMessageId.map(messageEntry.contains) ?? false
            )
        }
    }
}

/// A message with its avatar column, aligned by direction.
struct MessageRow: View {
    let entry: MessageEntry
    let chat: ChatItem
    let history: HistoryModel
    var isHighlighted = false

    @Environment(TelegramSession.self) private var session
    @Environment(MessageActionsModel.self) private var actions: MessageActionsModel?
    @Environment(\.chatThemeStyle) private var theme

    private var message: ChatMessage { entry.primary }
    private var isOutgoingStyle: Bool { message.isOutgoing && !chat.isChannel }
    private var showsAvatarColumn: Bool { chat.isGroup && !message.isOutgoing }
    /// Whether parts of the bubble stretch to whatever width they get (reply
    /// quotes, attachment footers, link previews, bot keyboards). Only then
    /// does the bubble's width need the costlier ideal-size measurement.
    private var hasInlineKeyboard: Bool {
        if case .replyMarkupInlineKeyboard = entry.captionMessage.replyMarkup { return true }
        return false
    }

    private var hasStretchingParts: Bool {
        if message.replyTo != nil || hasInlineKeyboard { return true }
        switch message.content {
        case .messageText(let value):
            return value.linkPreview != nil
        case .messagePhoto, .messageVideo, .messageAnimation, .messageSticker,
             .messageAnimatedEmoji, .messageDice, .messageVideoNote:
            return false
        default:
            return true
        }
    }

    /// Messages shows group senders as a small caption above the first bubble.
    private var showsSenderCaption: Bool {
        theme.isSystem && MessageBubble.showsSenderName(entry: entry, chat: chat)
    }
    private var isSelecting: Bool { actions?.isSelecting == true && !message.isService }
    private var isSelected: Bool {
        guard let actions else { return false }
        return entry.messages.allSatisfy { actions.selectedIds.contains($0.id) }
    }

    var body: some View {
        Group {
            if message.isService {
                ServiceCapsule(text: session.formatter(history: history).serviceText(for: message))
                    .padding(.vertical, 6)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .frame(maxHeight: .infinity, alignment: .center)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    if isOutgoingStyle { Spacer(minLength: 72) }
                    if showsAvatarColumn {
                        if entry.isLastInGroup {
                            AvatarView(content: session.avatar(of: message.senderId), size: 28)
                        } else {
                            Color.clear.frame(width: 28, height: 1)
                        }
                    }
                    // Hug short messages, wrap long ones at a comfortable width.
                    HuggingWidthLayout(maxWidth: 560, measuresIdealWidth: hasStretchingParts) {
                        VStack(alignment: isOutgoingStyle ? .trailing : .leading, spacing: 3) {
                            if showsSenderCaption {
                                Text(session.displayName(message.senderId))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                            }
                            MessageBubble(entry: entry, chat: chat, history: history, fillsWidth: hasInlineKeyboard)
                                .contextMenu {
                                    MessageContextMenu(entry: entry, chat: chat, history: history)
                                }
                            if case .replyMarkupInlineKeyboard(let keyboard) = entry.captionMessage.replyMarkup {
                                InlineKeyboardView(message: entry.captionMessage, rows: keyboard.rows)
                            }
                        }
                    }
                    if !isOutgoingStyle { Spacer(minLength: 72) }
                }
                .padding(.top, entry.isFirstInGroup ? 8 : 2)
            }
        }
        .overlay {
            // In selection mode a click anywhere on the row toggles it.
            if isSelecting {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { actions?.toggleSelection(of: entry.messages.map(\.id)) }
            }
        }
        .background {
            if isSelected || isHighlighted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ChatTheme.highlight)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -2)
            }
        }
        .animation(.easeOut(duration: 0.3), value: isHighlighted)
        .animation(.snappy, value: isSelecting)
        .onAppear {
            for item in entry.messages where !item.isOutgoing {
                history.markViewed(item.id)
            }
        }
        .task(id: entry.id) {
            guard !message.isService else { return }
            await history.loadProperties(for: entry.messages.map(\.id))
        }
    }
}

/// Service messages: a centered caption on the plain Messages background, or
/// tdesktop's translucent capsule over a wallpaper.
struct ServiceCapsule: View {
    let text: String

    @Environment(\.chatThemeStyle) private var theme

    var body: some View {
        if theme.isSystem {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
        } else {
            Text(text)
                .font(.callout)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(ChatTheme.serviceBackground, in: .capsule)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The date above a day of messages, also floated over the top of the
/// history while scrolling: a glass pill on the plain Messages background,
/// tdesktop's translucent capsule over a wallpaper.
struct DayHeader: View {
    let date: Date

    @Environment(\.chatThemeStyle) private var theme

    var body: some View {
        let label = Text(DateFormatting().daySeparator(date))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        Group {
            if theme.isSystem {
                label
                    .foregroundStyle(.secondary)
                    .glassEffect(.regular, in: .capsule)
            } else {
                label
                    .foregroundStyle(.white)
                    .background(ChatTheme.serviceBackground, in: .capsule)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The "Unread Messages" divider above the first unread message.
private struct UnreadSeparator: View {
    var body: some View {
        HStack(spacing: 10) {
            line
            Text("Unread Messages")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            line
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private var line: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
    }
}

/// Lays out one child at its ideal width, capped by `maxWidth` and the offered
/// width, so a bubble hugs a short message but wraps a long one instead of
/// overflowing the row (which `fixedSize` would do).
///
/// Measuring text is the most expensive part of scrolling the history, so
/// the width and the heights per width are cached until the row changes, the
/// zero-width probe stacks make never lays text out a glyph per line, and
/// rows without stretching parts are measured once, at `maxWidth`, instead
/// of also at their unconstrained single-line size.
struct HuggingWidthLayout: Layout {
    var maxWidth: CGFloat
    /// Set when parts of the child fill any width offered, so one measurement
    /// at `maxWidth` can't tell how wide the rest of it is.
    var measuresIdealWidth = true

    struct Cache {
        var fittedWidth: CGFloat?
        var heights: [CGFloat: CGFloat] = [:]
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let fitted = fittedWidth(child: child, cache: &cache)
        let width = min(fitted, proposal.width ?? fitted)
        // Stacks probe with a zero width to learn how far a child can shrink;
        // answer with the real height rather than laying out a 0-pt column.
        let height = self.height(at: width < 1 ? fitted : width, child: child, cache: &cache)
        return CGSize(width: max(0, width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }

    /// The width the child hugs, at most `maxWidth`.
    private func fittedWidth(child: LayoutSubview, cache: inout Cache) -> CGFloat {
        if let width = cache.fittedWidth { return width }
        let capped = child.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        // Round up: offering text exactly its measured width can rewrap it.
        var width = min(maxWidth, capped.width.rounded(.up))
        if width >= maxWidth - 0.5 {
            cache.heights[maxWidth.rounded()] = capped.height
            if measuresIdealWidth {
                width = min(maxWidth, child.sizeThatFits(.unspecified).width.rounded(.up))
            }
        } else {
            cache.heights[width.rounded()] = capped.height
        }
        cache.fittedWidth = width
        return width
    }

    private func height(at width: CGFloat, child: LayoutSubview, cache: inout Cache) -> CGFloat {
        let key = width.rounded()
        if let height = cache.heights[key] { return height }
        let height = child.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        cache.heights[key] = height
        return height
    }
}
