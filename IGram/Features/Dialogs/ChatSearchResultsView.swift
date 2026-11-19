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

    var body: some View {
        List {
            let chats = model.chatIds.compactMap(session.chats.chat)
            if !chats.isEmpty {
                Section("Chats") {
                    ForEach(chats) { chat in chatButton(chat) }
                }
            }
            let publicChats = model.publicChatIds.compactMap(session.chats.chat)
            if !publicChats.isEmpty {
                Section("Global Search") {
                    ForEach(publicChats) { chat in chatButton(chat) }
                }
            }
            if !model.messages.isEmpty {
                Section("Messages") {
                    ForEach(model.messages, id: \.id) { message in
                        messageButton(message)
                    }
                    Color.clear
                        .frame(height: 1)
                        .task(id: model.messages.count) { await model.loadMoreMessages(api: session.api) }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if model.isSearching, model.chatIds.isEmpty, model.messages.isEmpty {
                ProgressView()
            } else if !model.isSearching, model.chatIds.isEmpty, model.publicChatIds.isEmpty, model.messages.isEmpty {
                ContentUnavailableView.search
            }
        }
    }

    private func chatButton(_ chat: ChatItem) -> some View {
        Button {
            main.open(chatId: chat.id)
            Task { _ = try? await session.api.addRecentlyFoundChat(chatId: chat.id) }
        } label: {
            HStack(spacing: 10) {
                AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 36, isOnline: session.isOnline(chat))
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title(of: chat)).font(.body.weight(.medium)).lineLimit(1)
                    Text(subtitle(for: chat)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
        Button {
            main.open(chatId: message.chatId, messageId: message.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if let chat = session.chats.chat(message.chatId) {
                    AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(session.chats.chat(message.chatId).map(session.title(of:)) ?? "")
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(DateFormatting().chatListTimestamp(Date(timeIntervalSince1970: TimeInterval(message.date))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(session.formatter().preview(message.content))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
