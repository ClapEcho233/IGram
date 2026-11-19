//
//  MainView.swift
//  IGram
//

import QuickLook
import SwiftUI
@preconcurrency import TDLibKit

/// The signed-in main window: folders, chat list and the open chat.
struct MainView: View {
    @Environment(TelegramSession.self) private var session
    @State private var model = MainModel()
    @State private var audioPlayer = AudioPlayer()

    var body: some View {
        NavigationSplitView {
            FolderSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } content: {
            ChatListView(chatList: model.chatList, selection: $model.selectedChatId)
                .navigationTitle(navigationTitle)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
        } detail: {
            if let chatId = model.selectedChatId, let chat = session.chats.chat(chatId) {
                ChatView(chat: chat, history: session.history(for: chatId))
                    .id(chatId)
            } else {
                ContentUnavailableView(
                    "Select a chat to start messaging",
                    systemImage: "bubble.left.and.bubble.right"
                )
            }
        }
        .environment(model)
        .environment(audioPlayer)
        .quickLookPreview($model.quickLookURL)
        .environment(\.openURL, OpenURLAction { url in
            LinkRouter(session: session, main: model).handle(url)
        })
    }

    private var navigationTitle: String {
        switch model.sidebarSelection ?? .allChats {
        case .allChats: String(localized: "Chats")
        case .archive: String(localized: "Archived Chats")
        case .folder(let id):
            session.folders.folders.first { $0.id == id }?.name.text.text ?? String(localized: "Chats")
        }
    }
}
