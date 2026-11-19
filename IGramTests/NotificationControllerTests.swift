//
//  NotificationControllerTests.swift
//  IGramTests
//

import Foundation
import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct NotificationControllerTests {
    private let credentials = APICredentials(apiId: 12345, apiHash: String(repeating: "a", count: 32), useTestDC: true)

    @Test func identifierIncludesAccountAndChatPrefix() {
        let prefix = NotificationController.chatPrefix(accountIndex: 2, chatId: -100123)
        let id = NotificationController.identifier(accountIndex: 2, chatId: -100123, messageId: 99)
        #expect(id.hasPrefix(prefix))
        #expect(id != NotificationController.identifier(accountIndex: 1, chatId: -100123, messageId: 99))
    }

    @Test func unreadCountSumsAuthorizedAccounts() {
        let controller = NotificationController()
        let first = TelegramSession(credentials: credentials, accountIndex: 0)
        let second = TelegramSession(credentials: credentials, accountIndex: 1)
        let pending = TelegramSession(credentials: credentials, accountIndex: 2)

        first.handle(.updateAuthorizationState(UpdateAuthorizationState(authorizationState: .authorizationStateReady)))
        second.handle(.updateAuthorizationState(UpdateAuthorizationState(authorizationState: .authorizationStateReady)))
        pending.handle(.updateAuthorizationState(UpdateAuthorizationState(authorizationState: .authorizationStateWaitPhoneNumber)))

        first.handle(.updateUnreadMessageCount(UpdateUnreadMessageCount(chatList: .chatListMain, unreadCount: 5, unreadUnmutedCount: 2)))
        second.handle(.updateUnreadMessageCount(UpdateUnreadMessageCount(chatList: .chatListMain, unreadCount: 7, unreadUnmutedCount: 3)))
        pending.handle(.updateUnreadMessageCount(UpdateUnreadMessageCount(chatList: .chatListMain, unreadCount: 99, unreadUnmutedCount: 99)))

        controller.attach(first, requestSystemPermissions: false)
        controller.attach(second, requestSystemPermissions: false)
        controller.attach(pending, requestSystemPermissions: false)

        #expect(controller.unreadCount(includingMuted: false) == 5)
        #expect(controller.unreadCount(includingMuted: true) == 12)

        controller.detach(accountIndex: 1, updateSystemBadge: false)
        #expect(controller.unreadCount(includingMuted: false) == 2)
        #expect(controller.unreadCount(includingMuted: true) == 5)
    }
}
