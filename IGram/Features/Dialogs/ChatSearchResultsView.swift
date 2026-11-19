//
//  ChatSearchResultsView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Results of the global search shown in place of the chat list.
struct ChatSearchResultsView: View {
    let model: ChatSearchModel

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    /// Results are selectable rows rather than buttons: macOS lists clamp
    /// button rows to a single standard row height.
    @State private var selection: Result?

    private enum Result: Hashable {
        case chat(Int64)
        case message(chatId: Int64, messageId: Int64)
    }

    private enum Row: Identifiable {
        case header(String)
        case chat(ChatItem)
        case message(Message)
        case loadMore

        var id: String {
            switch self {
            case .header(let title): "header-\(title)"
            case .chat(let chat): "chat-\(chat.id)"
            case .message(let message): "message-\(message.chatId)-\(message.id)"
            case .loadMore: "load-more"
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        let chats = model.chatIds.compactMap(session.chats.chat)
        if !chats.isEmpty {
            rows.append(.header(String(localized: "Chats")))
            rows += chats.map(Row.chat)
        }
        let localIds = Set(model.chatIds)
        let publicChats = model.publicChatIds.filter { !localIds.contains($0) }.compactMap(session.chats.chat)
        if !publicChats.isEmpty {
            rows.append(.header(String(localized: "Global Search")))
            rows += publicChats.map(Row.chat)
        }
        if !model.messages.isEmpty {
            rows.append(.header(String(localized: "Messages")))
            rows += model.messages.map(Row.message)
            rows.append(.loadMore)
        }
        return rows
    }

    var body: some View {
        // One flat list: macOS doesn't auto-size rows nested in `Section`s,
        // which clipped avatars and previews to a single text line.
        List(selection: $selection) {
            ForEach(rows) { row in
                switch row {
                case .header(let title):
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                case .chat(let chat):
                    chatButton(chat)
                case .message(let message):
                    messageButton(message)
                case .loadMore:
                    Color.clear
                        .frame(height: 1)
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                        .task(id: model.messages.count) { await model.loadMoreMessages(api: session.api) }
                }
            }
        }
        .listStyle(.inset)
        .onChange(of: selection) { _, result in
            switch result {
            case .chat(let chatId):
                main.open(chatId: chatId)
                Task { _ = try? await session.api.addRecentlyFoundChat(chatId: chatId) }
            case .message(let chatId, let messageId):
                main.open(chatId: chatId, messageId: messageId)
            case nil:
                break
            }
        }
        .overlay {
            if model.isSearching, model.chatIds.isEmpty, model.messages.isEmpty {
                ProgressView()
            } else if !model.isSearching, model.chatIds.isEmpty, model.publicChatIds.isEmpty, model.messages.isEmpty {
                ContentUnavailableView.search
            }
        }
    }

    private func chatButton(_ chat: ChatItem) -> some View {
        HStack(spacing: 10) {
            AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 36, isOnline: session.isOnline(chat))
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title(of: chat)).font(.body.weight(.semibold)).lineLimit(1)
                let subtitle = subtitle(for: chat)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .tag(Result.chat(chat.id))
    }

    private func subtitle(for chat: ChatItem) -> String {
        if case .chatTypeSupergroup(let value) = chat.type,
           let username = session.peers.supergroup(value.supergroupId).supergroup?.usernames?.activeUsernames.first {
            return "@\(username)"
        }
        if let userId = chat.userId, let username = session.peers.user(userId).user?.username {
            return "@\(username)"
        }
        return session.subtitle(for: chat)
    }

    private func messageButton(_ message: Message) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let chat = session.chats.chat(message.chatId) {
                AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.chats.chat(message.chatId).map(session.title(of:)) ?? "")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(DateFormatting().chatListTimestamp(Date(timeIntervalSince1970: TimeInterval(message.date))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(session.formatter().preview(message.content))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .tag(Result.message(chatId: message.chatId, messageId: message.id))
    }
}
