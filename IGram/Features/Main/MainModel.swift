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
    var selectedChatId: Int64?
    var isInfoPresented = false
    /// A message to scroll to once its chat is open, e.g. from search results.
    var pendingMessageId: Int64?

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
