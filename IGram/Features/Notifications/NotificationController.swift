//
//  NotificationController.swift
//  IGram
//

import AppKit
import Foundation
import OSLog
@preconcurrency import TDLibKit
import UserNotifications

/// Posts system notifications for new messages of every signed-in account
/// and keeps the Dock badge, like tdesktop's `Window::Notifications::System`
/// with its native manager. tdesktop notifies about all accounts, not only
/// the one in the window, and so does IGram.
final class NotificationController: NSObject {
    /// A notification the user clicked, to open in its account.
    struct OpenRequest: Equatable {
        let accountIndex: Int
        let chatId: Int64
        let messageId: Int64?
    }

    /// Messages older than this are history sync, not news.
    static let freshnessWindow: TimeInterval = 120

    /// The navigation state of the window, for the active account.
    weak var main: MainModel?
    var activeAccountIndex = 0
    /// Called on the main actor when a notification was clicked.
    var onOpen: ((OpenRequest) -> Void)?

    private struct Attachment {
        weak var session: TelegramSession?
        let observer: UUID
    }

    private var attachments: [Int: Attachment] = [:]
    private var didRequestAuthorization = false
    private lazy var center = UNUserNotificationCenter.current()

    func attach(_ session: TelegramSession, requestSystemPermissions: Bool = true) {
        detach(accountIndex: session.accountIndex, updateSystemBadge: false)
        if requestSystemPermissions, !didRequestAuthorization {
            didRequestAuthorization = true
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
        let observer = session.addObserver { [weak self, weak session] update in
            guard let self, let session else { return }
            self.handle(update, in: session)
        }
        attachments[session.accountIndex] = Attachment(session: session, observer: observer)
        if requestSystemPermissions { updateBadge() }
    }

    func detach(accountIndex: Int, updateSystemBadge: Bool = true) {
        if let attachment = attachments.removeValue(forKey: accountIndex) {
            attachment.session?.removeObserver(attachment.observer)
        }
        if updateSystemBadge { updateBadge() }
    }

    private var sessions: [TelegramSession] {
        attachments.keys.sorted().compactMap { attachments[$0]?.session }
    }

    private func handle(_ update: Update, in session: TelegramSession) {
        switch update {
        case .updateNewMessage(let value):
            notify(about: value.message, in: session)
        case .updateChatReadInbox(let value):
            if value.unreadCount == 0 { removeNotifications(forChat: value.chatId, accountIndex: session.accountIndex) }
        case .updateUnreadMessageCount(let value) where value.chatList == .chatListMain:
            updateBadge()
        case .updateAuthorizationState:
            updateBadge()
        default:
            break
        }
    }

    // MARK: - Posting

    private func notify(about message: Message, in session: TelegramSession) {
        guard session.isAuthorized, UserDefaults.standard.bool(forKey: AppPreferences.notificationsEnabled) else { return }
        guard !message.isOutgoing,
              message.senderId.userId != session.myUserId,
              Date.now.timeIntervalSince1970 - TimeInterval(message.date) < Self.freshnessWindow,
              let chat = session.chats.chat(message.chatId),
              !session.chats.isMuted(chat) || message.containsUnreadMention
        else { return }
        let isActiveAccount = session.accountIndex == activeAccountIndex
        if NSApp.isActive, isActiveAccount, main?.selectedChatId == chat.id { return }

        let content = UNMutableNotificationContent()
        content.title = session.title(of: chat)
        var subtitle: [String] = []
        if chat.isGroup {
            subtitle.append(session.displayName(message.senderId))
        }
        if sessions.filter(\.isAuthorized).count > 1, !session.me.fullName.isEmpty {
            // Say which account received it, as tdesktop does with several accounts.
            subtitle.append(String(localized: "to \(session.me.fullName)"))
        }
        content.subtitle = subtitle.joined(separator: " · ")
        let chatMessage = ChatMessage(message)
        let formatter = session.formatter()
        content.body = UserDefaults.standard.bool(forKey: AppPreferences.notificationPreviews)
            ? (chatMessage.isService ? formatter.serviceText(for: chatMessage) : formatter.preview(message.content))
            : String(localized: "New message")
        if UserDefaults.standard.bool(forKey: AppPreferences.notificationSound) {
            content.sound = .default
        }
        content.threadIdentifier = "account-\(session.accountIndex)-chat-\(chat.id)"
        content.userInfo = ["accountIndex": session.accountIndex, "chatId": chat.id, "messageId": message.id]
        let request = UNNotificationRequest(
            identifier: Self.identifier(accountIndex: session.accountIndex, chatId: chat.id, messageId: message.id),
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error { Log.ui.error("Notification failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private func removeNotifications(forChat chatId: Int64, accountIndex: Int) {
        let prefix = Self.chatPrefix(accountIndex: accountIndex, chatId: chatId)
        center.getDeliveredNotifications { [center] delivered in
            let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    nonisolated static func chatPrefix(accountIndex: Int, chatId: Int64) -> String {
        "account-\(accountIndex)-chat-\(chatId)-"
    }

    nonisolated static func identifier(accountIndex: Int, chatId: Int64, messageId: Int64) -> String {
        chatPrefix(accountIndex: accountIndex, chatId: chatId) + "message-\(messageId)"
    }

    // MARK: - Badge

    /// Unread messages in the main lists of all signed-in accounts.
    func unreadCount(includingMuted: Bool) -> Int {
        sessions.filter(\.isAuthorized).reduce(0) { total, session in
            let list = session.chats.list(.chatListMain)
            return total + (includingMuted ? list.unreadMessageCount : list.unreadUnmutedMessageCount)
        }
    }

    func updateBadge() {
        let count = unreadCount(includingMuted: UserDefaults.standard.bool(forKey: AppPreferences.badgeIncludesMuted))
        NSApp?.dockTile.badgeLabel = count > 0 ? UnreadBadge.format(count) : nil
    }
}

extension NotificationController: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let accountIndex = (info["accountIndex"] as? NSNumber)?.intValue
        let chatId = (info["chatId"] as? NSNumber)?.int64Value
        let messageId = (info["messageId"] as? NSNumber)?.int64Value
        Task { @MainActor in
            NSApp.activate()
            if let chatId {
                self.onOpen?(OpenRequest(accountIndex: accountIndex ?? self.activeAccountIndex, chatId: chatId, messageId: messageId))
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
