//
//  ChatThemeTests.swift
//  IGramTests
//

import Foundation
import SwiftUI
import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct ChatThemeTests {
    private func solidBackground(id: Int64, color: Int, isDark: Bool = false) -> Background {
        Background(
            document: nil,
            id: TdInt64(id),
            isDark: isDark,
            isDefault: false,
            name: "bg-\(id)",
            type: .backgroundTypeFill(BackgroundTypeFill(fill: .backgroundFillSolid(BackgroundFillSolid(color: color))))
        )
    }

    private func themeSettings(accent: Int, outgoing: Int, background: Background?) -> ThemeSettings {
        ThemeSettings(
            accentColor: accent,
            animateOutgoingMessageFill: false,
            background: background,
            baseTheme: .builtInThemeClassic,
            hasOutgoingMessageAccentColor: false,
            outgoingMessageAccentColor: 0,
            outgoingMessageFill: .backgroundFillSolid(BackgroundFillSolid(color: outgoing))
        )
    }

    private func makeChat(id: Int64 = 1, theme: TDLibKit.ChatTheme? = nil, background: ChatBackground? = nil) -> Chat {
        Chat(
            accentColorId: 0, actionBar: nil, availableReactions: .chatAvailableReactionsAll(ChatAvailableReactionsAll(maxReactionCount: 11)),
            background: background, backgroundCustomEmojiId: 0, blockList: nil,
            businessBotManageBar: nil, canBeDeletedForAllUsers: true, canBeDeletedOnlyForSelf: true,
            canBeReported: false, chatLists: [], clientData: "", defaultDisableNotification: false,
            draftMessage: nil, emojiStatus: nil, hasProtectedContent: false, hasScheduledMessages: false,
            hasWelcomeMessages: false, id: id, isMarkedAsUnread: false, isTranslatable: false, lastMessage: nil,
            lastReadInboxMessageId: 0, lastReadOutboxMessageId: 0, messageAutoDeleteTime: 0,
            messageSenderId: nil,
            notificationSettings: ChatNotificationSettings(
                disableMentionNotifications: false, disablePinnedMessageNotifications: false, muteFor: 0,
                muteStories: false, showPreview: true, showStoryPoster: false, soundId: 0, storySoundId: 0,
                useDefaultDisableMentionNotifications: true, useDefaultDisablePinnedMessageNotifications: true,
                useDefaultMuteFor: true, useDefaultMuteStories: true, useDefaultShowPreview: true,
                useDefaultShowStoryPoster: true, useDefaultSound: true, useDefaultStorySound: true
            ),
            pendingJoinRequests: nil,
            permissions: ChatPermissions(
                canAddLinkPreviews: true, canChangeInfo: false, canCreateTopics: false, canEditTag: false,
                canInviteUsers: false, canPinMessages: false, canReactToMessages: true, canSendAudios: true,
                canSendBasicMessages: true, canSendDocuments: true, canSendOtherMessages: true,
                canSendPhotos: true, canSendPolls: true, canSendVideoNotes: true, canSendVideos: true,
                canSendVoiceNotes: true
            ),
            photo: nil, positions: [], profileAccentColorId: -1, profileBackgroundCustomEmojiId: 0,
            replyMarkupMessageId: 0, theme: theme, title: "Test",
            type: .chatTypePrivate(ChatTypePrivate(userId: 10)),
            unreadCount: 0, unreadMentionCount: 0, unreadPollVoteCount: 0, unreadReactionCount: 0,
            upgradedGiftColors: nil,
            videoChat: VideoChat(defaultParticipantId: nil, groupCallId: 0, hasParticipants: false),
            viewAsTopics: false
        )
    }

    @Test func detectsDarkVsLightLuminanceForTextContrast() {
        #expect(!ChatThemePalette.isDarkColor(0xEFFDDE))
        #expect(!ChatThemePalette.isDarkColor(0xFFFFFF))
        #expect(ChatThemePalette.isDarkColor(0x2B5278))
        #expect(ChatThemePalette.isDarkColor(0x182533))
        #expect(ChatThemePalette.isDarkColor(0x3B82F6))
    }

    @Test func resolvesPresetAndOverridesFromThemeSettings() {
        let classicLight = ChatThemePalette.resolved(preset: .classic, settings: nil, isDark: false)
        #expect(!classicLight.outgoingNeedsLightText)

        let dayLight = ChatThemePalette.resolved(preset: .day, settings: nil, isDark: false)
        #expect(dayLight.outgoingNeedsLightText)

        let settings = themeSettings(accent: 0xFF6B00, outgoing: 0x1A2B3C, background: nil)
        let themed = ChatThemePalette.resolved(preset: .classic, settings: settings, isDark: false)
        #expect(themed.incomingAccent == 0xFF6B00)
        #expect(themed.outgoingBubble == .solid(0x1A2B3C))
        #expect(themed.outgoingNeedsLightText)
    }

    @Test func gradientAnglesMapToUnitPoints() {
        let down = BackgroundGeometry.gradientPoints(forAngle: 0)
        #expect(abs(down.start.x - 0.5) < 0.001 && abs(down.start.y - 0.0) < 0.001)
        #expect(abs(down.end.x - 0.5) < 0.001 && abs(down.end.y - 1.0) < 0.001)

        let right = BackgroundGeometry.gradientPoints(forAngle: 90)
        #expect(abs(right.start.x - 0.0) < 0.001 && abs(right.start.y - 0.5) < 0.001)
        #expect(abs(right.end.x - 1.0) < 0.001 && abs(right.end.y - 0.5) < 0.001)
    }

    @Test func themeStoreResolvesPrecedenceAcrossChatThemeAndDefaults() {
        let store = ThemeStore()
        let defaultLight = solidBackground(id: 1, color: 0xDDEECC)
        let defaultDark = solidBackground(id: 2, color: 0x112233, isDark: true)
        let themeBg = solidBackground(id: 3, color: 0xFFEEDD)
        let chatBg = solidBackground(id: 4, color: 0xABCDEF)

        store.handle(.updateDefaultBackground(UpdateDefaultBackground(background: defaultLight, forDarkTheme: false)))
        store.handle(.updateDefaultBackground(UpdateDefaultBackground(background: defaultDark, forDarkTheme: true)))
        store.handle(.updateEmojiChatThemes(UpdateEmojiChatThemes(chatThemes: [
            EmojiChatTheme(
                darkSettings: themeSettings(accent: 0x9988FF, outgoing: 0x223344, background: defaultDark),
                lightSettings: themeSettings(accent: 0xAA44CC, outgoing: 0x334455, background: themeBg),
                name: "🦄"
            ),
        ])))

        let plainChat = ChatItem(chat: makeChat(id: 1))
        #expect(store.resolvedBackground(for: plainChat, isDark: false)?.background.id == defaultLight.id)
        #expect(store.resolvedBackground(for: plainChat, isDark: true)?.background.id == defaultDark.id)

        let themedChat = ChatItem(chat: makeChat(id: 2, theme: .chatThemeEmoji(ChatThemeEmoji(name: "🦄"))))
        #expect(store.themeSettings(for: themedChat, isDark: false)?.accentColor == 0xAA44CC)
        #expect(store.resolvedBackground(for: themedChat, isDark: false)?.background.id == themeBg.id)

        let customChat = ChatItem(chat: makeChat(
            id: 3,
            theme: .chatThemeEmoji(ChatThemeEmoji(name: "🦄")),
            background: ChatBackground(background: chatBg, darkThemeDimming: 40)
        ))
        let resolved = store.resolvedBackground(for: customChat, isDark: false)
        #expect(resolved?.background.id == chatBg.id)
        #expect(resolved?.darkDimming == 40)
    }

    @Test func chatStoreUpdatesThemeAndBackground() {
        let chats = ChatStore(client: TelegramClient())
        chats.handle(.updateNewChat(UpdateNewChat(chat: makeChat(id: 7))))
        let bg = ChatBackground(background: solidBackground(id: 9, color: 0x123456), darkThemeDimming: 25)
        chats.handle(.updateChatTheme(UpdateChatTheme(chatId: 7, theme: .chatThemeEmoji(ChatThemeEmoji(name: "🔥")))))
        chats.handle(.updateChatBackground(UpdateChatBackground(background: bg, chatId: 7)))

        #expect(chats.chat(7)?.theme == .chatThemeEmoji(ChatThemeEmoji(name: "🔥")))
        #expect(chats.chat(7)?.background == bg)
    }
}
