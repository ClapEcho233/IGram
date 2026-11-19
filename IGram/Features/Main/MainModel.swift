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
    /// A proxy from a tg://proxy or t.me/socks link, awaiting confirmation.
    var proxyToAdd: ProxyDraft?
    /// An embedded Telegram Mini App (Web App) open in a sheet.
    var webApp: WebAppRequest?
    /// Active Telegram Stories viewer sheet.
    var storyViewer: StoryViewerRequest?
    /// A sticker set preview sheet (from tapping a sticker or t.me/addstickers link).
    var stickerSet: StickerSetTarget?
    /// A chat invite link awaiting confirmation before joining.
    var inviteLink: InviteLinkRequest?
    /// Text to place into a chat's composer (e.g. from a Mini App inline switch).
    var pendingComposerText: ComposerDraft?
    /// A short message shown over the window, like tdesktop's `Ui::Toast`.
    private(set) var toast: Toast?

    struct ComposerDraft: Equatable {
        let id = UUID()
        let chatId: Int64
        let text: String
    }

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

    func openWebApp(title: String, launch: WebAppLaunch) {
        webApp = WebAppRequest(title: title.isEmpty ? String(localized: "Web App") : title, launch: launch)
    }

    func openStories(chatIds: [Int64], startingAt chatId: Int64) {
        let peers = chatIds.isEmpty ? [chatId] : chatIds
        storyViewer = StoryViewerRequest(chatIds: peers, initialChatId: chatId, initialStoryId: nil)
    }

    func openStory(posterChatId: Int64, storyId: Int) {
        storyViewer = StoryViewerRequest(chatIds: [posterChatId], initialChatId: posterChatId, initialStoryId: storyId)
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
