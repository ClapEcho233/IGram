//
//  MainView.swift
//  IGram
//

import QuickLook
import SwiftUI
@preconcurrency import TDLibKit

/// The signed-in main window: the chat list with folder tabs, and the open chat.
struct MainView: View {
    @Environment(TelegramSession.self) private var session
    @State private var model = MainModel()
    @State private var audioPlayer = AudioPlayer()
    @State private var search = ChatSearchModel()
    @Environment(AppModel.self) private var app
    @State private var navigation: ChatNavigation?
    @AppStorage(AppPreferences.badgeIncludesMuted) private var badgeIncludesMuted = false

    var body: some View {
        NavigationSplitView {
            Group {
                if model.searchText.isEmpty {
                    ChatListView(chatList: model.chatList, selection: $model.selectedChatId)
                } else {
                    ChatSearchResultsView(model: search)
                }
            }
            // Messages keeps its search field at the top of the conversation
            // list; folders sit right below it as tabs.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ChatListSearchField(text: $model.searchText)
                    if model.searchText.isEmpty {
                        FolderBar(model: model)
                    }
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                AccountFooter()
            }
            .scrollEdgeEffectStyle(.hard, for: .bottom)
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
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
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
        // The open chat shows its own centered header; the system title would
        // repeat it at the leading edge. The window keeps its title for menus.
        .toolbar(removing: .title)
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
        .onAppear {
            let navigation = ChatNavigation(session: session, model: model)
            self.navigation = navigation
            app.navigation = navigation
            app.notifications.main = model
            openPendingNotification()
        }
        .onDisappear {
            if app.notifications.main === model { app.notifications.main = nil }
            if let navigation, app.navigation === navigation { app.navigation = nil }
        }
        .onChange(of: app.pendingOpen) { openPendingNotification() }
        .onChange(of: badgeIncludesMuted) { app.notifications.updateBadge() }
        .quickLookPreview($model.quickLookURL)
        .sheet(isPresented: Binding(get: { model.proxyToAdd != nil }, set: { if !$0 { model.proxyToAdd = nil } })) {
            if let draft = model.proxyToAdd {
                AddProxySheet(draft: draft)
            }
        }
        .sheet(item: $model.newChat) { kind in
            NewChatSheet(kind: kind)
                .environment(model)
        }
        .sheet(item: $model.webApp) { request in
            WebAppSheet(request: request)
                .environment(model)
        }
        .sheet(item: $model.storyViewer) { request in
            StoryViewerSheet(request: request)
                .environment(model)
        }
        .sheet(item: $model.stickerSet) { target in
            StickerSetSheet(target: target)
                .environment(model)
        }
        .sheet(item: $model.inviteLink) { request in
            InviteLinkSheet(request: request)
                .environment(model)
        }
        .environment(\.openURL, OpenURLAction { url in
            LinkRouter(session: session, main: model).handle(url)
        })
    }

    /// Opens the chat of a clicked notification once its account is shown.
    private func openPendingNotification() {
        guard let request = app.pendingOpen, request.accountIndex == session.accountIndex else { return }
        app.pendingOpen = nil
        model.open(chatId: request.chatId, messageId: request.messageId)
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

/// The search field above the chat list.
private struct ChatListSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand {
                    text = ""
                    isFocused = false
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.quaternary.opacity(0.7), in: .capsule)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background {
            // Typing ⌥⌘F anywhere jumps here, like Find in other apps' sidebars.
            Button("Search Chats") { isFocused = true }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .hidden()
        }
    }
}
