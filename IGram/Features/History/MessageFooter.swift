//
//  MessageFooter.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Time, edit mark, views and delivery state in the corner of a bubble.
struct MessageFooter: View {
    let message: ChatMessage
    let chat: ChatItem
    let isOutgoingStyle: Bool
    /// Draws the footer as a dark capsule over media.
    var overMedia = false

    @Environment(TelegramSession.self) private var session

    var body: some View {
        HStack(spacing: 3) {
            if let views = message.interactionInfo?.viewCount, views > 0, chat.isChannel {
                Image(systemName: "eye")
                Text(Self.compact(views))
            }
            if message.isEdited {
                Text("edited")
            }
            if message.isPinned {
                Image(systemName: "pin.fill")
            }
            Text(DateFormatting().time(message.dateValue))
            if message.isOutgoing, !chat.isChannel, !session.isSavedMessages(chat) {
                deliveryIcon
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(overMedia ? AnyShapeStyle(.white) : AnyShapeStyle(ChatTheme.secondary(outgoing: isOutgoingStyle)))
        .padding(.horizontal, overMedia ? 6 : 0)
        .padding(.vertical, overMedia ? 2 : 0)
        .background {
            if overMedia { Capsule().fill(.black.opacity(0.45)) }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var deliveryIcon: some View {
        if message.isFailed {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        } else if message.isSending {
            Image(systemName: "clock")
        } else if message.id <= chat.lastReadOutboxMessageId {
            Image(systemName: "checkmark.message.fill")
        } else {
            Image(systemName: "checkmark")
        }
    }

    /// Invisible text reserving room for the footer at the end of the last line,
    /// so short messages keep the time on the same line like tdesktop.
    static func placeholder(for message: ChatMessage, chat: ChatItem) -> String {
        var parts: [String] = []
        if chat.isChannel, let views = message.interactionInfo?.viewCount, views > 0 { parts.append("👁 \(compact(views))") }
        if message.isEdited { parts.append(String(localized: "edited")) }
        if message.isPinned { parts.append("📌") }
        parts.append(DateFormatting().time(message.dateValue))
        if message.isOutgoing, !chat.isChannel { parts.append("✓✓") }
        return "\u{2003}" + parts.joined(separator: " ")
    }

    static func compact(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}
