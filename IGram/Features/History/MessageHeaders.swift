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
    @Environment(\.chatThemeStyle) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Forwarded from")
                .font(.caption)
                .foregroundStyle(theme.secondary(outgoing: isOutgoingStyle))
            Text(originName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.accent(outgoing: isOutgoingStyle))
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
    @Environment(MainModel.self) private var main
    @Environment(\.chatThemeStyle) private var theme

    var body: some View {
        switch message.replyTo {
        case .messageReplyToMessage(let reply):
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
                            .foregroundStyle(theme.primaryText(outgoing: isOutgoingStyle).opacity(0.82))
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
        case .messageReplyToStory(let reply):
            let accent = theme.accent(outgoing: isOutgoingStyle)
            Button {
                main.openStory(posterChatId: reply.storyPosterChatId, storyId: reply.storyId)
            } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accent)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.chats.chat(reply.storyPosterChatId).map { session.title(of: $0) } ?? String(localized: "Story"))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                        Text("Story")
                            .font(.callout)
                            .foregroundStyle(theme.primaryText(outgoing: isOutgoingStyle).opacity(0.82))
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 3)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.12), in: .rect(cornerRadius: 4))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        case nil:
            EmptyView()
        }
    }

    private func accent(for replied: ChatMessage?) -> Color {
        guard !isOutgoingStyle, let replied else { return theme.accent(outgoing: isOutgoingStyle) }
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
