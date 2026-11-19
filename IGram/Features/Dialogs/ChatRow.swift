//
//  ChatRow.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// One chat in the chat list, after tdesktop's `Dialogs::Ui::PaintRow`.
struct ChatRow: View {
    let chat: ChatItem
    let chatList: ChatList

    @Environment(TelegramSession.self) private var session

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(
                content: .chat(chat, myUserId: session.myUserId),
                size: 48,
                isOnline: session.isOnline(chat)
            )
            VStack(alignment: .leading, spacing: 2) {
                titleLine
                previewLine
            }
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
    }

    // MARK: - Title line

    private var titleLine: some View {
        HStack(spacing: 4) {
            if let icon = typeIcon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(chat.isSecret ? .green : .secondary)
            }
            Text(session.title(of: chat))
                .font(.body.weight(.semibold))
                .lineLimit(1)
            if isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
            if session.chats.isMuted(chat) {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            deliveryIcon
            if let message = chat.lastMessage {
                Text(DateFormatting().chatListTimestamp(Date(timeIntervalSince1970: TimeInterval(message.date))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var typeIcon: String? {
        switch chat.type {
        case .chatTypeSecret: "lock.fill"
        case .chatTypeBasicGroup: "person.2.fill"
        case .chatTypeSupergroup(let value): value.isChannel ? "megaphone.fill" : "person.2.fill"
        case .chatTypePrivate(let value):
            session.peers.user(value.userId).user?.isBot == true ? "cpu" : nil
        }
    }

    private var isVerified: Bool {
        switch chat.type {
        case .chatTypePrivate(let value):
            session.peers.user(value.userId).user?.verificationStatus?.isVerified == true
        case .chatTypeSupergroup(let value):
            session.peers.supergroup(value.supergroupId).supergroup?.verificationStatus?.isVerified == true
        default:
            false
        }
    }

    @ViewBuilder
    private var deliveryIcon: some View {
        if let message = chat.lastMessage, message.isOutgoing, !session.isSavedMessages(chat), !chat.isChannel {
            switch message.sendingState {
            case .messageSendingStatePending:
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .messageSendingStateFailed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            case nil:
                Image(systemName: message.id <= chat.lastReadOutboxMessageId ? "checkmark.message" : "checkmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
    }

    // MARK: - Preview line

    private var previewLine: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(preview)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            badges
        }
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            if chat.unreadMentionCount > 0 {
                Image(systemName: "at")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.tint, in: .circle)
            }
            if chat.unreadReactionCount > 0 {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.red, in: .circle)
            }
            if chat.unreadCount > 0 || chat.isMarkedAsUnread {
                UnreadBadge(count: chat.unreadCount, isMuted: session.chats.isMuted(chat))
            } else if chat.isPinned(in: chatList) {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(45))
            }
        }
    }

    private var preview: AttributedString {
        if let action = session.actionText(for: chat) {
            var text = AttributedString(action)
            text.foregroundColor = .accentColor
            return text
        }
        if let draft = draftText, chat.unreadCount == 0 {
            var prefix = AttributedString(String(localized: "Draft: "))
            prefix.foregroundColor = .red
            return prefix + AttributedString(draft)
        }
        guard let message = chat.lastMessage else { return AttributedString(" ") }

        let formatter = session.formatter()
        let chatMessage = ChatMessage(message)
        if chatMessage.isService {
            return AttributedString(formatter.serviceText(for: chatMessage))
        }

        var result = AttributedString()
        if let sender = senderPrefix(for: message) {
            var prefix = AttributedString("\(sender): ")
            prefix.foregroundColor = .primary
            result += prefix
        }
        result += AttributedString(formatter.preview(message.content))
        return result
    }

    /// "You" or the sender's first name, shown in groups like tdesktop does.
    private func senderPrefix(for message: Message) -> String? {
        if message.isOutgoing {
            return chat.isChannel || chat.userId != nil ? nil : String(localized: "You")
        }
        guard chat.isGroup else { return nil }
        return session.shortName(message.senderId)
    }

    private var draftText: String? {
        guard case .draftMessageContentText(let content) = chat.draftMessage?.content else { return nil }
        let text = content.text.text.singleLine
        return text.isEmpty ? nil : text
    }
}
