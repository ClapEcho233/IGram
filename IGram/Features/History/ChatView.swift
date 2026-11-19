//
//  ChatView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// An open chat: header, history and (later) the composer.
/// Corresponds to tdesktop's `HistoryWidget`.
struct ChatView: View {
    let chat: ChatItem
    let history: HistoryModel

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @State private var unreadAnchor: Int64?

    var body: some View {
        VStack(spacing: 0) {
            HistoryView(chat: chat, history: history, unreadAnchor: unreadAnchor)
        }
        .navigationTitle(session.title(of: chat))
        .navigationSubtitle(session.subtitle(for: chat))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 28)
            }
        }
        .task(id: chat.id) {
            unreadAnchor = chat.unreadCount > 0 ? chat.lastReadInboxMessageId : nil
            await history.open(unreadCount: chat.unreadCount, lastReadInboxMessageId: chat.lastReadInboxMessageId)
            await jumpToPendingMessage()
        }
        .onChange(of: main.pendingMessageId) {
            Task { await jumpToPendingMessage() }
        }
        .onDisappear { history.close() }
        .task(id: chat.userId) {
            // Keep presence and profile details fresh while the chat is open.
            if let userId = chat.userId {
                _ = try? await session.api.getUserFullInfo(userId: userId)
            }
        }
    }

    private func jumpToPendingMessage() async {
        guard let messageId = main.pendingMessageId, main.selectedChatId == chat.id else { return }
        main.pendingMessageId = nil
        await history.jump(to: messageId)
    }
}
