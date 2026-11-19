//
//  ChatStore.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// Observable state of one chat, the counterpart of tdesktop's `History`/`PeerData`
/// pair as seen from the chat list.
@Observable
final class ChatItem: Identifiable {
    let id: Int64
    let type: ChatType

    fileprivate(set) var title: String
    fileprivate(set) var photo: ChatPhotoInfo?
    fileprivate(set) var accentColorId: Int
    fileprivate(set) var lastMessage: Message?
    fileprivate(set) var positions: [ChatPosition]
    fileprivate(set) var chatLists: [ChatList]
    fileprivate(set) var unreadCount: Int
    fileprivate(set) var unreadMentionCount: Int
    fileprivate(set) var unreadReactionCount: Int
    fileprivate(set) var lastReadInboxMessageId: Int64
    fileprivate(set) var lastReadOutboxMessageId: Int64
    fileprivate(set) var isMarkedAsUnread: Bool
    fileprivate(set) var notificationSettings: ChatNotificationSettings
    fileprivate(set) var draftMessage: DraftMessage?
    fileprivate(set) var permissions: ChatPermissions
    fileprivate(set) var availableReactions: ChatAvailableReactions
    fileprivate(set) var hasProtectedContent: Bool
    fileprivate(set) var defaultDisableNotification: Bool
    fileprivate(set) var messageSenderId: MessageSender?
    fileprivate(set) var emojiStatus: EmojiStatus?
    fileprivate(set) var messageAutoDeleteTime: Int
    fileprivate(set) var pendingJoinRequests: ChatJoinRequestsInfo?
    fileprivate(set) var actionBar: ChatActionBar?
    fileprivate(set) var blockList: BlockList?
    fileprivate(set) var onlineMemberCount = 0
    fileprivate(set) var hasScheduledMessages: Bool
    /// Forums shown as a list of topics rather than one message stream.
    fileprivate(set) var viewAsTopics: Bool
    /// The message whose reply keyboard is shown under the composer (bots).
    fileprivate(set) var replyMarkupMessageId: Int64
    fileprivate(set) var replyMarkupMessage: Message?
    /// Ongoing actions ("typing…", "sending photo…") keyed by sender.
    fileprivate(set) var actions: [MessageSender: ChatAction] = [:]
    let canBeDeletedForAllUsers: Bool
    let canBeDeletedOnlyForSelf: Bool

    init(chat: Chat) {
        id = chat.id
        type = chat.type
        title = chat.title
        photo = chat.photo
        accentColorId = chat.accentColorId
        lastMessage = chat.lastMessage
        positions = chat.positions
        chatLists = chat.chatLists
        unreadCount = chat.unreadCount
        unreadMentionCount = chat.unreadMentionCount
        unreadReactionCount = chat.unreadReactionCount
        lastReadInboxMessageId = chat.lastReadInboxMessageId
        lastReadOutboxMessageId = chat.lastReadOutboxMessageId
        isMarkedAsUnread = chat.isMarkedAsUnread
        notificationSettings = chat.notificationSettings
        draftMessage = chat.draftMessage
        permissions = chat.permissions
        availableReactions = chat.availableReactions
        hasProtectedContent = chat.hasProtectedContent
        defaultDisableNotification = chat.defaultDisableNotification
        messageSenderId = chat.messageSenderId
        emojiStatus = chat.emojiStatus
        messageAutoDeleteTime = chat.messageAutoDeleteTime
        pendingJoinRequests = chat.pendingJoinRequests
        actionBar = chat.actionBar
        blockList = chat.blockList
        replyMarkupMessageId = chat.replyMarkupMessageId
        hasScheduledMessages = chat.hasScheduledMessages
        viewAsTopics = chat.viewAsTopics
        canBeDeletedForAllUsers = chat.canBeDeletedForAllUsers
        canBeDeletedOnlyForSelf = chat.canBeDeletedOnlyForSelf
    }

    func position(in list: ChatList) -> ChatPosition? {
        positions.first { $0.list == list }
    }

    func isPinned(in list: ChatList) -> Bool {
        position(in: list)?.isPinned ?? false
    }

    var userId: Int64? {
        switch type {
        case .chatTypePrivate(let value): value.userId
        case .chatTypeSecret(let value): value.userId
        default: nil
        }
    }

    var isChannel: Bool {
        if case .chatTypeSupergroup(let value) = type { return value.isChannel }
        return false
    }

    var isGroup: Bool {
        switch type {
        case .chatTypeBasicGroup: true
        case .chatTypeSupergroup(let value): !value.isChannel
        default: false
        }
    }

    var isSecret: Bool {
        if case .chatTypeSecret = type { return true }
        return false
    }

    var hasUnread: Bool { unreadCount > 0 || isMarkedAsUnread }
}

/// All chats of the session and their ordered chat lists.
///
/// Implements the chat-list half of tdesktop's `Data::Session`, following the
/// update rules from TDLib's "getting started" guide.
final class ChatStore {
    private let client: TelegramClient
    private var items: [Int64: ChatItem] = [:]
    private var lists: [ChatList: ChatListModel] = [:]
    private var scopeMuteFor: [NotificationSettingsScope: Int] = [:]

    init(client: TelegramClient) {
        self.client = client
    }

    func chat(_ id: Int64) -> ChatItem? { items[id] }

    func list(_ list: ChatList) -> ChatListModel {
        if let model = lists[list] { return model }
        let model = ChatListModel(list: list)
        for item in items.values {
            if let position = item.position(in: list) {
                model.setPosition(chatId: item.id, order: position.order.rawValue, isPinned: position.isPinned)
            }
        }
        lists[list] = model
        return model
    }

    /// Asks TDLib for the next page of `list`. Chats arrive through updates.
    func loadMore(_ chatList: ChatList, limit: Int = 50) async {
        let model = list(chatList)
        guard !model.isLoading, !model.isComplete else { return }
        model.setLoading(true)
        defer { model.setLoading(false) }
        do {
            try await client.api.loadChats(chatList: chatList, limit: limit)
        } catch let error as TDError where error.code == 404 {
            model.markComplete()
        } catch {
            Log.data.error("loadChats failed: \(error.telegramMessage, privacy: .public)")
        }
    }

    /// Whether notifications for the chat are muted, resolving scope defaults.
    func isMuted(_ chat: ChatItem) -> Bool {
        let settings = chat.notificationSettings
        let muteFor = settings.useDefaultMuteFor ? (scopeMuteFor[scope(of: chat)] ?? 0) : settings.muteFor
        return muteFor > 0
    }

    private func scope(of chat: ChatItem) -> NotificationSettingsScope {
        switch chat.type {
        case .chatTypePrivate, .chatTypeSecret: .notificationSettingsScopePrivateChats
        case .chatTypeBasicGroup: .notificationSettingsScopeGroupChats
        case .chatTypeSupergroup(let value):
            value.isChannel ? .notificationSettingsScopeChannelChats : .notificationSettingsScopeGroupChats
        }
    }

    // MARK: - Updates

    @discardableResult
    func handle(_ update: Update) -> Bool {
        switch update {
        case .updateNewChat(let value):
            let item = ChatItem(chat: value.chat)
            items[item.id] = item
            setPositions(value.chat.positions, of: item)
        case .updateChatTitle(let value):
            items[value.chatId]?.title = value.title
        case .updateChatPhoto(let value):
            items[value.chatId]?.photo = value.photo
        case .updateChatAccentColors(let value):
            items[value.chatId]?.accentColorId = value.accentColorId
        case .updateChatPermissions(let value):
            items[value.chatId]?.permissions = value.permissions
        case .updateChatLastMessage(let value):
            guard let item = items[value.chatId] else { break }
            item.lastMessage = value.lastMessage
            setPositions(value.positions, of: item)
        case .updateChatPosition(let value):
            guard let item = items[value.chatId] else { break }
            var positions = item.positions.filter { $0.list != value.position.list }
            if value.position.order.rawValue != 0 { positions.append(value.position) }
            setPositions(positions, of: item)
        case .updateChatAddedToList(let value):
            guard let item = items[value.chatId], !item.chatLists.contains(value.chatList) else { break }
            item.chatLists.append(value.chatList)
        case .updateChatRemovedFromList(let value):
            items[value.chatId]?.chatLists.removeAll { $0 == value.chatList }
        case .updateChatReadInbox(let value):
            guard let item = items[value.chatId] else { break }
            item.lastReadInboxMessageId = value.lastReadInboxMessageId
            item.unreadCount = value.unreadCount
        case .updateChatReadOutbox(let value):
            items[value.chatId]?.lastReadOutboxMessageId = value.lastReadOutboxMessageId
        case .updateChatUnreadMentionCount(let value):
            items[value.chatId]?.unreadMentionCount = value.unreadMentionCount
        case .updateMessageMentionRead(let value):
            items[value.chatId]?.unreadMentionCount = value.unreadMentionCount
        case .updateChatUnreadReactionCount(let value):
            items[value.chatId]?.unreadReactionCount = value.unreadReactionCount
        case .updateMessageUnreadReactions(let value):
            items[value.chatId]?.unreadReactionCount = value.unreadReactionCount
        case .updateChatIsMarkedAsUnread(let value):
            items[value.chatId]?.isMarkedAsUnread = value.isMarkedAsUnread
        case .updateChatNotificationSettings(let value):
            items[value.chatId]?.notificationSettings = value.notificationSettings
        case .updateScopeNotificationSettings(let value):
            scopeMuteFor[value.scope] = value.notificationSettings.muteFor
        case .updateChatDraftMessage(let value):
            guard let item = items[value.chatId] else { break }
            item.draftMessage = value.draftMessage
            setPositions(value.positions, of: item)
        case .updateChatAvailableReactions(let value):
            items[value.chatId]?.availableReactions = value.availableReactions
        case .updateChatHasProtectedContent(let value):
            items[value.chatId]?.hasProtectedContent = value.hasProtectedContent
        case .updateChatDefaultDisableNotification(let value):
            items[value.chatId]?.defaultDisableNotification = value.defaultDisableNotification
        case .updateChatMessageSender(let value):
            items[value.chatId]?.messageSenderId = value.messageSenderId
        case .updateChatEmojiStatus(let value):
            items[value.chatId]?.emojiStatus = value.emojiStatus
        case .updateChatMessageAutoDeleteTime(let value):
            items[value.chatId]?.messageAutoDeleteTime = value.messageAutoDeleteTime
        case .updateChatPendingJoinRequests(let value):
            items[value.chatId]?.pendingJoinRequests = value.pendingJoinRequests
        case .updateChatActionBar(let value):
            items[value.chatId]?.actionBar = value.actionBar
        case .updateChatBlockList(let value):
            items[value.chatId]?.blockList = value.blockList
        case .updateChatViewAsTopics(let value):
            items[value.chatId]?.viewAsTopics = value.viewAsTopics
        case .updateChatHasScheduledMessages(let value):
            items[value.chatId]?.hasScheduledMessages = value.hasScheduledMessages
        case .updateChatReplyMarkup(let value):
            guard let item = items[value.chatId] else { break }
            item.replyMarkupMessage = value.replyMarkupMessage
            item.replyMarkupMessageId = value.replyMarkupMessage?.id ?? 0
        case .updateChatOnlineMemberCount(let value):
            items[value.chatId]?.onlineMemberCount = value.onlineMemberCount
        case .updateChatAction(let value):
            guard let item = items[value.chatId], value.topicId == nil else { break }
            if case .chatActionCancel = value.action {
                item.actions[value.senderId] = nil
            } else {
                item.actions[value.senderId] = value.action
            }
        case .updateUnreadMessageCount(let value):
            list(value.chatList).setUnreadMessageCount(total: value.unreadCount, unmuted: value.unreadUnmutedCount)
        case .updateUnreadChatCount(let value):
            list(value.chatList).setUnreadChatCount(total: value.unreadCount, unmuted: value.unreadUnmutedCount)
        default:
            return false
        }
        return true
    }

    /// Replaces the chat's positions and re-sorts every affected list.
    private func setPositions(_ positions: [ChatPosition], of item: ChatItem) {
        let removedLists = item.positions.map(\.list).filter { list in
            !positions.contains { $0.list == list }
        }
        item.positions = positions
        for list in removedLists {
            lists[list]?.setPosition(chatId: item.id, order: 0, isPinned: false)
        }
        for position in positions {
            list(position.list).setPosition(
                chatId: item.id,
                order: position.order.rawValue,
                isPinned: position.isPinned
            )
        }
    }
}
