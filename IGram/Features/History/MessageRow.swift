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
            ServiceCapsule(text: DateFormatting().daySeparator(date), isHeader: true)
                .padding(.top, 14)
                .padding(.bottom, 6)
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
                    HuggingWidthLayout(maxWidth: 560) {
                        VStack(alignment: isOutgoingStyle ? .trailing : .leading, spacing: 3) {
                            if showsSenderCaption {
                                Text(session.displayName(message.senderId))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                            }
                            MessageBubble(entry: entry, chat: chat, history: history)
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

/// Service messages and day headers: a centered caption on the plain
/// Messages background, or tdesktop's translucent capsule over a wallpaper.
struct ServiceCapsule: View {
    let text: String
    /// Day headers are slightly more prominent than service messages.
    var isHeader = false

    @Environment(\.chatThemeStyle) private var theme

    var body: some View {
        if theme.isSystem {
            Text(text)
                .font(isHeader ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
        } else {
            Text(text)
                .font(isHeader ? .callout.weight(.medium) : .callout)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(ChatTheme.serviceBackground, in: .capsule)
                .frame(maxWidth: .infinity)
        }
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
struct HuggingWidthLayout: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = width(for: proposal, child: child)
        let height = child.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }

    private func width(for proposal: ProposedViewSize, child: LayoutSubview) -> CGFloat {
        let limit = min(maxWidth, proposal.width ?? maxWidth)
        let ideal = child.sizeThatFits(.unspecified).width
        return max(0, min(limit, ideal))
    }
}
