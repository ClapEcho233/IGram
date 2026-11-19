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
            ServiceCapsule(text: DateFormatting().daySeparator(date))
                .font(.callout.weight(.medium))
                .padding(.vertical, 6)
        case .unread:
            Text("Unread Messages")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.bar)
                .padding(.vertical, 6)
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

    private var message: ChatMessage { entry.primary }
    private var isOutgoingStyle: Bool { message.isOutgoing && !chat.isChannel }
    private var showsAvatarColumn: Bool { chat.isGroup && !message.isOutgoing }

    var body: some View {
        Group {
            if message.isService {
                ServiceCapsule(text: session.formatter(history: history).serviceText(for: message))
                    .font(.callout)
                    .padding(.vertical, 4)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    if isOutgoingStyle { Spacer(minLength: 64) }
                    if showsAvatarColumn {
                        if entry.isLastInGroup {
                            AvatarView(content: session.avatar(of: message.senderId), size: 34)
                        } else {
                            Color.clear.frame(width: 34, height: 1)
                        }
                    }
                    MessageBubble(entry: entry, chat: chat, history: history)
                    if !isOutgoingStyle { Spacer(minLength: 64) }
                }
                .padding(.top, entry.isFirstInGroup ? 6 : 1)
            }
        }
        .padding(.horizontal, 4)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 8).fill(ChatTheme.highlight)
                    .padding(.horizontal, -8)
            }
        }
        .animation(.easeOut(duration: 0.3), value: isHighlighted)
        .onAppear {
            for item in entry.messages where !item.isOutgoing {
                history.markViewed(item.id)
            }
        }
    }
}

/// The translucent capsule used for service messages and day headers.
struct ServiceCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ChatTheme.serviceBackground, in: .capsule)
            .frame(maxWidth: .infinity)
    }
}
