//
//  NotificationController.swift
//  IGram
//

import AppKit
import Foundation
import OSLog
@preconcurrency import TDLibKit
import UserNotifications

/// Posts system notifications for new messages and keeps the Dock badge,
/// like tdesktop's `Window::Notifications::System` and its native manager.
final class NotificationController: NSObject {
    private weak var session: TelegramSession?
    private weak var main: MainModel?
    private var observer: UUID?
    private let center = UNUserNotificationCenter.current()

    /// Messages older than this are history sync, not news.
    static let freshnessWindow: TimeInterval = 120

    func attach(session: TelegramSession, main: MainModel) {
        detach()
        self.session = session
        self.main = main
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        observer = session.addObserver { [weak self] update in
            self?.handle(update)
        }
        updateBadge()
    }

    func detach() {
        if let observer { session?.removeObserver(observer) }
        observer = nil
        NSApp.dockTile.badgeLabel = nil
    }

    private func handle(_ update: Update) {
        switch update {
        case .updateNewMessage(let value):
            notify(about: value.message)
        case .updateChatReadInbox(let value):
            if value.unreadCount == 0 { removeNotifications(forChat: value.chatId) }
        case .updateUnreadMessageCount(let value) where value.chatList == .chatListMain:
            updateBadge()
        default:
            break
        }
    }

    // MARK: - Posting

    private func notify(about message: Message) {
        guard let session, UserDefaults.standard.bool(forKey: AppPreferences.notificationsEnabled) else { return }
        guard !message.isOutgoing,
              message.senderId.userId != session.myUserId,
              Date.now.timeIntervalSince1970 - TimeInterval(message.date) < Self.freshnessWindow,
              let chat = session.chats.chat(message.chatId),
              !session.chats.isMuted(chat) || message.containsUnreadMention
        else { return }
        if NSApp.isActive, main?.selectedChatId == chat.id { return }

        let content = UNMutableNotificationContent()
        content.title = session.title(of: chat)
        if chat.isGroup {
            content.subtitle = session.displayName(message.senderId)
        }
        let chatMessage = ChatMessage(message)
        let formatter = session.formatter()
        content.body = UserDefaults.standard.bool(forKey: AppPreferences.notificationPreviews)
            ? (chatMessage.isService ? formatter.serviceText(for: chatMessage) : formatter.preview(message.content))
            : String(localized: "New message")
        if UserDefaults.standard.bool(forKey: AppPreferences.notificationSound) {
            content.sound = .default
        }
        content.threadIdentifier = "chat-\(chat.id)"
        content.userInfo = ["chatId": chat.id, "messageId": message.id]
        let request = UNNotificationRequest(
            identifier: Self.identifier(chatId: chat.id, messageId: message.id),
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error { Log.ui.error("Notification failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private func removeNotifications(forChat chatId: Int64) {
        let prefix = "chat-\(chatId)-"
        center.getDeliveredNotifications { [center] delivered in
            let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    static func identifier(chatId: Int64, messageId: Int64) -> String {
        "chat-\(chatId)-message-\(messageId)"
    }

    // MARK: - Badge

    func updateBadge() {
        guard let session else { return }
        let list = session.chats.list(.chatListMain)
        let count = UserDefaults.standard.bool(forKey: AppPreferences.badgeIncludesMuted)
            ? list.unreadMessageCount
            : list.unreadUnmutedMessageCount
        NSApp.dockTile.badgeLabel = count > 0 ? UnreadBadge.format(count) : nil
    }
}

extension NotificationController: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let chatId = (info["chatId"] as? NSNumber)?.int64Value
        let messageId = (info["messageId"] as? NSNumber)?.int64Value
        Task { @MainActor in
            NSApp.activate()
            if let chatId { self.main?.open(chatId: chatId, messageId: messageId) }
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
