//
//  ChatActions.swift
//  IGram
//

import Foundation
import OSLog
@preconcurrency import TDLibKit

/// Chat-level actions offered by the chat list, like tdesktop's
/// `Window::FillDialogsEntryMenu`.
extension TelegramSession {
    /// Notifications are muted "forever" with any duration above a year.
    static let muteForever = Int(Int32.max)

    func setPinned(_ chat: ChatItem, in list: ChatList, pinned: Bool) async throws {
        try await api.toggleChatIsPinned(chatId: chat.id, chatList: list, isPinned: pinned)
    }

    func setMuted(_ chat: ChatItem, muted: Bool) async throws {
        let current = chat.notificationSettings
        let settings = ChatNotificationSettings(
            disableMentionNotifications: current.disableMentionNotifications,
            disablePinnedMessageNotifications: current.disablePinnedMessageNotifications,
            muteFor: muted ? Self.muteForever : 0,
            muteStories: current.muteStories,
            showPreview: current.showPreview,
            showStoryPoster: current.showStoryPoster,
            soundId: current.soundId,
            storySoundId: current.storySoundId,
            useDefaultDisableMentionNotifications: current.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: current.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: false,
            useDefaultMuteStories: current.useDefaultMuteStories,
            useDefaultShowPreview: current.useDefaultShowPreview,
            useDefaultShowStoryPoster: current.useDefaultShowStoryPoster,
            useDefaultSound: current.useDefaultSound,
            useDefaultStorySound: current.useDefaultStorySound
        )
        try await api.setChatNotificationSettings(chatId: chat.id, notificationSettings: settings)
    }

    func setArchived(_ chat: ChatItem, archived: Bool) async throws {
        try await api.addChatToList(chatId: chat.id, chatList: archived ? .chatListArchive : .chatListMain)
    }

    func isArchived(_ chat: ChatItem) -> Bool {
        chat.position(in: .chatListArchive) != nil
    }

    func markAsRead(_ chat: ChatItem) async throws {
        if let last = chat.lastMessage {
            try await api.viewMessages(chatId: chat.id, forceRead: true, messageIds: [last.id], source: .messageSourceChatList)
        }
        if chat.unreadMentionCount > 0 {
            try await api.readAllChatMentions(chatId: chat.id)
        }
        if chat.isMarkedAsUnread {
            try await api.toggleChatIsMarkedAsUnread(chatId: chat.id, isMarkedAsUnread: false)
        }
    }

    func markAsUnread(_ chat: ChatItem) async throws {
        try await api.toggleChatIsMarkedAsUnread(chatId: chat.id, isMarkedAsUnread: true)
    }

    /// Clears the history for the current user and removes the chat from the list.
    func deleteChat(_ chat: ChatItem, forEveryone: Bool = false) async throws {
        archive.expectHistoryCleared(chatId: chat.id)
        if chat.isSecret, case .chatTypeSecret(let secret) = chat.type {
            try await api.closeSecretChat(secretChatId: secret.secretChatId)
        }
        try await api.deleteChatHistory(chatId: chat.id, removeFromChatList: true, revoke: forEveryone)
    }

    func leave(_ chat: ChatItem) async throws {
        try await api.leaveChat(chatId: chat.id)
    }

    /// Whether the user can leave the chat rather than just delete it.
    func canLeave(_ chat: ChatItem) -> Bool {
        switch chat.type {
        case .chatTypeBasicGroup(let value):
            guard let status = peers.basicGroup(value.basicGroupId).group?.status else { return true }
            return status.isMember
        case .chatTypeSupergroup(let value):
            guard let status = peers.supergroup(value.supergroupId).supergroup?.status else { return true }
            return status.isMember
        default:
            return false
        }
    }
}

extension ChatMemberStatus {
    var isMember: Bool {
        switch self {
        case .chatMemberStatusCreator(let value): value.isMember
        case .chatMemberStatusAdministrator, .chatMemberStatusMember: true
        case .chatMemberStatusRestricted(let value): value.isMember
        case .chatMemberStatusLeft, .chatMemberStatusBanned: false
        }
    }
}
