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
    @State private var navigation: ChatNavigation?
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
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("New Message", systemImage: "square.and.pencil") { model.newChat = .message }
                        Button("New Group", systemImage: "person.2") { model.newChat = .group }
                        Button("New Channel", systemImage: "megaphone") { model.newChat = .channel }
                        Button("New Secret Chat", systemImage: "lock") { model.newChat = .secretChat }
                        Divider()
                        Button("Add Contact", systemImage: "person.badge.plus") { model.newChat = .contact }
                    } label: {
                        Label("New", systemImage: "square.and.pencil")
                    }
                    .help("New message, group or channel")
                }
            }
            .task(id: model.searchText) { await search.search(model.searchText, api: session.api) }
            .navigationTitle(navigationTitle)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
        } detail: {
            if let chatId = model.selectedChatId, let chat = session.chats.chat(chatId) {
                if session.showsTopics(chat) {
                    if let topic = model.selectedTopic {
                        ChatView(chat: chat, history: session.history(for: chatId, topicId: topic.forumTopicId), topic: topic)
                            .id("\(chatId)-\(topic.forumTopicId)")
                    } else {
                        ForumTopicsView(chat: chat)
                            .id(chatId)
                    }
                } else {
                    ChatView(chat: chat, history: session.history(for: chatId))
                        .id(chatId)
                }
            } else {
                ContentUnavailableView(
                    "Select a chat to start messaging",
                    systemImage: "bubble.left.and.bubble.right"
                )
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast.text)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.75), in: .rect(cornerRadius: 10))
                    .padding(.top, 60)
                    .frame(maxWidth: 420)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .id(toast.id)
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: model.toast)
        .environment(model)
        .environment(audioPlayer)
        .focusedSceneValue(\.chatNavigation, navigation)
        .onAppear {
            navigation = ChatNavigation(session: session, model: model)
            notifications.attach(session: session, main: model)
        }
        .onDisappear { notifications.detach() }
        .onChange(of: badgeIncludesMuted) { notifications.updateBadge() }
        .quickLookPreview($model.quickLookURL)
        .sheet(item: $model.newChat) { kind in
            NewChatSheet(kind: kind)
                .environment(model)
        }
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
