//
//  ChatCommands.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Navigation actions of the focused main window, exposed to the menu bar.
@MainActor
final class ChatNavigation {
    private let session: TelegramSession
    private let model: MainModel

    init(session: TelegramSession, model: MainModel) {
        self.session = session
        self.model = model
    }

    var folderTabs: [ChatFolderTab] {
        let tabs = session.folders.tabs
        return tabs.isEmpty ? [.all] : tabs
    }

    /// Moves the selection `offset` chats down (positive) or up the current list.
    func selectAdjacentChat(_ offset: Int) {
        let ids = session.chats.list(model.chatList).chatIds
        guard !ids.isEmpty else { return }
        guard let current = model.selectedChatId, let index = ids.firstIndex(of: current) else {
            model.open(chatId: offset > 0 ? ids[0] : ids[ids.count - 1])
            return
        }
        let next = min(max(index + offset, 0), ids.count - 1)
        model.open(chatId: ids[next])
    }

    func openSavedMessages() {
        let userId = session.myUserId
        Task {
            if let chat = try? await session.api.createPrivateChat(force: false, userId: userId) {
                model.open(chatId: chat.id)
            }
        }
    }

    func showArchive() { model.sidebarSelection = .archive }

    func showFolder(at index: Int) {
        let tabs = folderTabs
        guard tabs.indices.contains(index) else { return }
        model.sidebarSelection = tabs[index].sidebarItem
    }

    func markAllAsRead() {
        let list = model.chatList
        Task {
            do {
                try await session.api.readChatList(chatList: list)
            } catch {
                Log.ui.error("readChatList failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }

    func closeChat() { model.selectedChatId = nil }

    func startNewChat(_ kind: NewChatKind) { model.newChat = kind }
}

/// The "Chats" menu, with tdesktop's shortcuts adapted to the Command key.
struct ChatCommands: Commands {
    let app: AppModel

    private var navigation: ChatNavigation? { app.navigation }

    var body: some Commands {
        // Not disabled while signed out: AppKit keeps a menu item's first
        // enabled state until the menu is opened, which swallowed ⌘N.
        CommandGroup(replacing: .newItem) {
            Button("New Message") { navigation?.startNewChat(.message) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Group") { navigation?.startNewChat(.group) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Channel") { navigation?.startNewChat(.channel) }
            Button("New Secret Chat") { navigation?.startNewChat(.secretChat) }
        }
        CommandMenu("Chats") {
            Button("Next Chat") { navigation?.selectAdjacentChat(1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous Chat") { navigation?.selectAdjacentChat(-1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Close Chat") { navigation?.closeChat() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("Saved Messages") { navigation?.openSavedMessages() }
                .keyboardShortcut("0", modifiers: .command)
            if let navigation {
                ForEach(Array(navigation.folderTabs.prefix(9).enumerated()), id: \.offset) { index, tab in
                    Button(tab.title) { navigation.showFolder(at: index) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            Button("Archived Chats") { navigation?.showArchive() }
            Divider()
            Button("Mark All as Read") { navigation?.markAllAsRead() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
