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
    @State private var search = ChatSearchModel()
    @State private var notifications = NotificationController()
    @AppStorage(AppPreferences.badgeIncludesMuted) private var badgeIncludesMuted = false

    var body: some View {
        NavigationSplitView {
            FolderSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } content: {
            Group {
                if model.searchText.isEmpty {
                    ChatListView(chatList: model.chatList, selection: $model.selectedChatId)
                } else {
                    ChatSearchResultsView(model: search)
                }
            }
            .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Search"))
            .task(id: model.searchText) { await search.search(model.searchText, api: session.api) }
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
        .onAppear { notifications.attach(session: session, main: model) }
        .onDisappear { notifications.detach() }
        .onChange(of: badgeIncludesMuted) { notifications.updateBadge() }
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
