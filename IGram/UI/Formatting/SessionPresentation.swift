//
//  SessionPresentation.swift
//  IGram
//

import Foundation
@preconcurrency import TDLibKit

/// Display helpers that combine several stores, the way tdesktop's
/// `PeerData::name()` and `Ui::Text` helpers consult the data session.
extension TelegramSession {
    var me: UserItem { peers.user(myUserId) }

    func isSavedMessages(_ chat: ChatItem) -> Bool {
        chat.userId == myUserId && !chat.isSecret
    }

    func title(of chat: ChatItem) -> String {
        isSavedMessages(chat) ? String(localized: "Saved Messages") : chat.title
    }

    func userName(_ userId: Int64) -> String {
        guard let user = peers.user(userId).user else { return "" }
        if user.isDeleted { return String(localized: "Deleted Account") }
        return user.fullName
    }

    /// Short name for compact places such as "Alice: hi".
    func shortName(_ sender: MessageSender) -> String {
        switch sender {
        case .messageSenderUser(let value):
            if value.userId == myUserId { return String(localized: "You") }
            let user = peers.user(value.userId).user
            if let first = user?.firstName, !first.isEmpty { return first }
            return userName(value.userId)
        case .messageSenderChat(let value):
            return chats.chat(value.chatId)?.title ?? ""
        }
    }

    func displayName(_ sender: MessageSender) -> String {
        switch sender {
        case .messageSenderUser(let value): userName(value.userId)
        case .messageSenderChat(let value): chats.chat(value.chatId)?.title ?? ""
        }
    }

    func accentColorId(of sender: MessageSender) -> Int {
        switch sender {
        case .messageSenderUser(let value): peers.user(value.userId).user?.accentColorId ?? Int(value.userId % 7)
        case .messageSenderChat(let value): chats.chat(value.chatId)?.accentColorId ?? Int(value.chatId % 7)
        }
    }

    func avatar(of sender: MessageSender) -> AvatarContent {
        switch sender {
        case .messageSenderUser(let value):
            return .user(peers.user(value.userId).user)
        case .messageSenderChat(let value):
            guard let chat = chats.chat(value.chatId) else { return .photo(nil, title: "", accentColorId: 0) }
            return .photo(chat.photo, title: chat.title, accentColorId: chat.accentColorId)
        }
    }

    func formatter(history: HistoryModel? = nil) -> MessageFormatter {
        MessageFormatter(
            userName: { [weak self] in self?.userName($0) ?? "" },
            chatTitle: { [weak self] in self?.chats.chat($0)?.title ?? "" },
            messagePreview: { [weak self, weak history] id in
                guard let self, let message = history?.message(id) else { return nil }
                return self.formatter().preview(message.content)
            }
        )
    }

    /// Whether to draw the online dot: private chats with an online human.
    func isOnline(_ chat: ChatItem) -> Bool {
        guard let userId = chat.userId, userId != myUserId else { return false }
        let item = peers.user(userId)
        guard item.user?.isBot != true else { return false }
        return DateFormatting.isOnline(item.status)
    }

    /// "typing…", "Alice is typing…", "Alice and Bob are typing…".
    func actionText(for chat: ChatItem) -> String? {
        let senders = chat.actions.keys.filter { $0.userId != myUserId }
        guard let first = senders.first, let action = chat.actions[first] else { return nil }
        let verb = Self.describe(action)
        if chat.userId != nil {
            return "\(verb)…"
        }
        if senders.count == 1 {
            return String(localized: "\(shortName(first)) is \(verb)…")
        }
        if senders.count == 2, let second = senders.dropFirst().first {
            return String(localized: "\(shortName(first)) and \(shortName(second)) are \(verb)…")
        }
        return String(localized: "\(senders.count) people are \(verb)…")
    }

    static func describe(_ action: ChatAction) -> String {
        switch action {
        case .chatActionTyping: String(localized: "typing")
        case .chatActionRecordingVideo, .chatActionRecordingVideoNote: String(localized: "recording video")
        case .chatActionUploadingVideo, .chatActionUploadingVideoNote: String(localized: "sending video")
        case .chatActionRecordingVoiceNote: String(localized: "recording voice")
        case .chatActionUploadingVoiceNote: String(localized: "sending voice")
        case .chatActionUploadingPhoto: String(localized: "sending photo")
        case .chatActionUploadingDocument: String(localized: "sending file")
        case .chatActionChoosingSticker: String(localized: "choosing sticker")
        case .chatActionChoosingLocation: String(localized: "choosing location")
        case .chatActionChoosingContact: String(localized: "choosing contact")
        case .chatActionStartPlayingGame: String(localized: "playing a game")
        case .chatActionWatchingAnimations: String(localized: "watching animations")
        case .chatActionCancel: String(localized: "typing")
        }
    }

    /// Header subtitle: presence for users, member count for groups and channels.
    func subtitle(for chat: ChatItem) -> String {
        if isSavedMessages(chat) { return "" }
        if let action = actionText(for: chat) { return action }
        switch chat.type {
        case .chatTypePrivate, .chatTypeSecret:
            guard let userId = chat.userId else { return "" }
            let item = peers.user(userId)
            if let user = item.user {
                if user.isBot { return String(localized: "bot") }
                if user.isSupport { return String(localized: "support") }
            }
            return DateFormatting().presence(item.status)
        case .chatTypeBasicGroup(let value):
            let count = peers.basicGroup(value.basicGroupId).group?.memberCount ?? 0
            return membersText(count, online: chat.onlineMemberCount)
        case .chatTypeSupergroup(let value):
            let supergroup = peers.supergroup(value.supergroupId)
            let count = supergroup.fullInfo?.memberCount ?? supergroup.supergroup?.memberCount ?? 0
            if value.isChannel {
                return count > 0 ? String(localized: "\(count) subscribers") : String(localized: "channel")
            }
            return membersText(count, online: chat.onlineMemberCount)
        }
    }

    private func membersText(_ count: Int, online: Int) -> String {
        guard count > 0 else { return String(localized: "group") }
        if online > 1 {
            return String(localized: "\(count) members, \(online) online")
        }
        return String(localized: "\(count) members")
    }
}
