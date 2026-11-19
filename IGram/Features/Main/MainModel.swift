//
//  MainModel.swift
//  IGram
//

import Foundation
import Observation
@preconcurrency import TDLibKit

/// Navigation state of the main window, like tdesktop's `Window::SessionController`.
@Observable
final class MainModel {
    enum SidebarItem: Hashable {
        case allChats
        case folder(Int)
        case archive
    }

    var sidebarSelection: SidebarItem? = .allChats
    var selectedChatId: Int64? {
        didSet {
            if selectedChatId != oldValue { selectedTopic = nil }
        }
    }
    /// The open forum topic of the selected chat, if it's a forum.
    var selectedTopic: ForumTopicInfo?
    var isInfoPresented = false
    /// A message to scroll to once its chat is open, e.g. from search results.
    var pendingMessageId: Int64?
    /// A downloaded file shown in Quick Look (photos, videos, documents).
    var quickLookURL: URL?
    /// Text of the global search field above the chat list.
    var searchText = ""
    /// The chat creation sheet being shown.
    var newChat: NewChatKind?
    /// A short message shown over the window, like tdesktop's `Ui::Toast`.
    private(set) var toast: Toast?

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    func showToast(_ text: String) {
        let toast = Toast(text: text)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if self.toast == toast { self.toast = nil }
        }
    }

    var chatList: ChatList {
        switch sidebarSelection ?? .allChats {
        case .allChats: .chatListMain
        case .folder(let id): .chatListFolder(ChatListFolder(chatFolderId: id))
        case .archive: .chatListArchive
        }
    }

    func open(chatId: Int64, messageId: Int64? = nil) {
        selectedChatId = chatId
        pendingMessageId = messageId
    }
}

extension ChatFolderTab {
    var sidebarItem: MainModel.SidebarItem {
        switch self {
        case .all: .allChats
        case .folder(let info): .folder(info.id)
        }
    }
}
