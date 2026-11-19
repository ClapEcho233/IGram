//
//  MessageHeaders.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// "Forwarded from …" line at the top of a bubble.
struct ForwardHeader: View {
    let info: MessageForwardInfo
    let isOutgoingStyle: Bool

    @Environment(TelegramSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Forwarded from")
                .font(.caption)
                .foregroundStyle(ChatTheme.secondary(outgoing: isOutgoingStyle))
            Text(originName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(ChatTheme.accent(outgoing: isOutgoingStyle))
                .lineLimit(1)
        }
    }

    private var originName: String {
        switch info.origin {
        case .messageOriginUser(let value): session.userName(value.senderUserId)
        case .messageOriginHiddenUser(let value): value.senderName
        case .messageOriginChat(let value): session.chats.chat(value.senderChatId)?.title ?? ""
        case .messageOriginChannel(let value):
            [session.chats.chat(value.chatId)?.title ?? "", value.authorSignature]
                .filter { !$0.isEmpty }
                .joined(separator: " – ")
        }
    }
}

/// Quoted reply preview at the top of a bubble; clicking it jumps to the original.
struct ReplyHeader: View {
    let message: ChatMessage
    let history: HistoryModel
    let isOutgoingStyle: Bool

    @Environment(TelegramSession.self) private var session

    var body: some View {
        if case .messageReplyToMessage(let reply) = message.replyTo {
            let replied = history.repliedMessage(for: message)
            Button {
                guard reply.chatId == history.chatId else { return }
                Task { await history.jump(to: reply.messageId) }
            } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accent(for: replied))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(senderName(reply: reply, replied: replied))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(accent(for: replied))
                            .lineLimit(1)
                        Text(previewText(reply: reply, replied: replied))
                            .font(.callout)
                            .foregroundStyle(.primary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 3)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent(for: replied).opacity(0.12), in: .rect(cornerRadius: 4))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func accent(for replied: ChatMessage?) -> Color {
        guard !isOutgoingStyle, let replied else { return ChatTheme.accent(outgoing: isOutgoingStyle) }
        return PeerColor.name(session.accentColorId(of: replied.senderId))
    }

    private func senderName(reply: MessageReplyToMessage, replied: ChatMessage?) -> String {
        if let replied { return session.displayName(replied.senderId) }
        if let origin = reply.origin {
            switch origin {
            case .messageOriginUser(let value): return session.userName(value.senderUserId)
            case .messageOriginHiddenUser(let value): return value.senderName
            case .messageOriginChat(let value): return session.chats.chat(value.senderChatId)?.title ?? ""
            case .messageOriginChannel(let value): return session.chats.chat(value.chatId)?.title ?? ""
            }
        }
        return String(localized: "Loading…")
    }

    private func previewText(reply: MessageReplyToMessage, replied: ChatMessage?) -> String {
        if let quote = reply.quote, !quote.text.text.isEmpty { return quote.text.text.singleLine }
        let formatter = session.formatter(history: history)
        if let replied {
            return replied.isService ? formatter.serviceText(for: replied) : formatter.preview(replied.content)
        }
        if let content = reply.content { return formatter.preview(content) }
        return reply.messageId == 0 ? String(localized: "Deleted message") : " "
    }
}
