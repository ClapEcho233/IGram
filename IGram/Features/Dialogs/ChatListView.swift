//
//  ChatListView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// The chats of one list, paged in from TDLib as the user scrolls,
/// like tdesktop's `Dialogs::InnerWidget`.
struct ChatListView: View {
    let chatList: ChatList
    @Binding var selection: Int64?

    @Environment(TelegramSession.self) private var session
    @State private var pendingRemoval: ChatRemoval?

    var body: some View {
        let list = session.chats.list(chatList)
        let chats = list.chatIds.compactMap(session.chats.chat)
        VStack(spacing: 0) {
            if let storyList {
                StoriesBar(storyList: storyList)
            }
            List(selection: $selection) {
                ForEach(chats) { chat in
                    ChatRow(chat: chat, chatList: chatList)
                        .tag(chat.id)
                        .contextMenu {
                            ChatContextMenu(chat: chat, chatList: chatList) { pendingRemoval = $0 }
                        }
                }
                if !list.isComplete {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        // Re-runs whenever a page arrives while the spinner is still visible.
                        .task(id: list.chatIds.count) {
                            await session.chats.loadMore(chatList)
                        }
                }
            }
            .listStyle(.inset)
            .overlay {
                if list.isComplete, chats.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "bubble.left.and.bubble.right")
                }
            }
        }
        .chatRemovalConfirmation($pendingRemoval, session: session)
    }

    private var storyList: StoryList? {
        switch chatList {
        case .chatListMain: .storyListMain
        case .chatListArchive: .storyListArchive
        case .chatListFolder: nil
        }
    }

    private var emptyTitle: String {
        switch chatList {
        case .chatListArchive: String(localized: "No Archived Chats")
        case .chatListFolder: String(localized: "No Chats in This Folder")
        case .chatListMain: String(localized: "No Chats Yet")
        }
    }
}
