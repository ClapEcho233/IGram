//
//  ChatFolderStore.swift
//  IGram
//

import Foundation
import Observation
@preconcurrency import TDLibKit

/// A tab in the folder strip: "All chats" or a user-defined folder.
enum ChatFolderTab: Hashable, Identifiable {
    case all
    case folder(ChatFolderInfo)

    var id: Int {
        switch self {
        case .all: -1
        case .folder(let info): info.id
        }
    }

    var chatList: ChatList {
        switch self {
        case .all: .chatListMain
        case .folder(let info): .chatListFolder(ChatListFolder(chatFolderId: info.id))
        }
    }

    var title: String {
        switch self {
        case .all: String(localized: "All Chats")
        case .folder(let info): info.name.text.text
        }
    }

    /// SF Symbol for TDLib's folder icon names, approximating tdesktop's filter icons.
    var systemImage: String {
        switch self {
        case .all: return "bubble.left.and.bubble.right"
        case .folder(let info):
            switch info.icon.name {
            case "All": return "bubble.left.and.bubble.right"
            case "Unread": return "envelope.badge"
            case "Unmuted": return "bell"
            case "Bots": return "cpu"
            case "Channels": return "megaphone"
            case "Groups": return "person.3"
            case "Private": return "person"
            case "Setup": return "list.bullet"
            case "Cat": return "cat"
            case "Crown": return "crown"
            case "Favorite": return "star"
            case "Flower": return "camera.macro"
            case "Game": return "gamecontroller"
            case "Home": return "house"
            case "Love": return "heart"
            case "Mask": return "theatermasks"
            case "Party": return "party.popper"
            case "Sport": return "sportscourt"
            case "Study": return "graduationcap"
            case "Trade": return "chart.line.uptrend.xyaxis"
            case "Travel": return "airplane"
            case "Work": return "briefcase"
            case "Airplane": return "airplane"
            case "Book": return "book"
            case "Light": return "lightbulb"
            case "Like": return "hand.thumbsup"
            case "Money": return "dollarsign.circle"
            case "Note": return "music.note"
            case "Palette": return "paintpalette"
            default: return "folder"
            }
        }
    }
}

/// Chat folders configured by the user, like tdesktop's `Data::ChatFilters`.
@Observable
final class ChatFolderStore {
    private(set) var folders: [ChatFolderInfo] = []
    /// Index of "All chats" among the folders, chosen by the user on other clients.
    private(set) var mainChatListPosition = 0
    private(set) var areTagsEnabled = false

    /// Tabs in display order, or an empty list when no folders exist.
    var tabs: [ChatFolderTab] {
        Self.tabs(folders: folders, mainChatListPosition: mainChatListPosition)
    }

    static func tabs(folders: [ChatFolderInfo], mainChatListPosition: Int) -> [ChatFolderTab] {
        guard !folders.isEmpty else { return [] }
        var tabs = folders.map(ChatFolderTab.folder)
        tabs.insert(.all, at: min(max(mainChatListPosition, 0), tabs.count))
        return tabs
    }

    @discardableResult
    func handle(_ update: Update) -> Bool {
        guard case .updateChatFolders(let value) = update else { return false }
        folders = value.chatFolders
        mainChatListPosition = value.mainChatListPosition
        areTagsEnabled = value.areTagsEnabled
        return true
    }
}
