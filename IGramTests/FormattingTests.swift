//
//  FormattingTests.swift
//  IGramTests
//

import Foundation
import SwiftUI
import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct FormattedTextTests {
    private func entity(_ offset: Int, _ length: Int, _ type: TextEntityType) -> TextEntity {
        TextEntity(length: length, offset: offset, type: type)
    }

    @Test func plainTextIsUnchanged() {
        let result = FormattedText(entities: [], text: "Hello").attributedString()
        #expect(String(result.characters) == "Hello")
    }

    @Test func boldUsesUTF16Offsets() {
        // "👋" is two UTF-16 code units, so "world" starts at offset 9.
        let text = FormattedText(entities: [entity(9, 5, .textEntityTypeBold)], text: "Hello 👋 world")
        let result = text.attributedString()
        let bold = result.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        #expect(bold.count == 1)
        if let run = bold.first {
            #expect(String(result[run.range].characters) == "world")
        }
    }

    @Test func outOfRangeEntitiesAreIgnored() {
        let text = FormattedText(entities: [entity(3, 50, .textEntityTypeItalic)], text: "short")
        let result = text.attributedString()
        #expect(result.runs.allSatisfy { $0.inlinePresentationIntent == nil })
    }

    @Test func urlEntitiesBecomeLinks() {
        let text = FormattedText(entities: [entity(6, 12, .textEntityTypeUrl)], text: "Visit telegram.org now")
        let links = text.attributedString().runs.compactMap(\.link)
        #expect(links == [URL(string: "https://telegram.org")!])
    }

    @Test func textUrlUsesTargetURL() {
        let text = FormattedText(
            entities: [entity(0, 4, .textEntityTypeTextUrl(TextEntityTypeTextUrl(url: "https://example.com/a")))],
            text: "here"
        )
        #expect(text.attributedString().runs.compactMap(\.link) == [URL(string: "https://example.com/a")!])
    }

    @Test func mentionsBecomeInternalLinks() {
        let text = FormattedText(
            entities: [
                entity(0, 6, .textEntityTypeMention),
                entity(7, 3, .textEntityTypeMentionName(TextEntityTypeMentionName(userId: 42))),
            ],
            text: "@durov Bob"
        )
        let links = text.attributedString().runs.compactMap(\.link).compactMap(InternalLink.init(url:))
        #expect(links == [.username("durov"), .user(42)])
    }

    @Test func internalLinkRoundTrip() {
        for link in [InternalLink.user(7), .username("alice"), .hashtag("#swift"), .botCommand("/start")] {
            #expect(link.url.flatMap(InternalLink.init(url:)) == link)
        }
        #expect(InternalLink(url: URL(string: "https://telegram.org")!) == nil)
    }

    @Test func webURLAddsScheme() {
        #expect(FormattedText.webURL(from: "telegram.org") == URL(string: "https://telegram.org"))
        #expect(FormattedText.webURL(from: "http://a.b/c") == URL(string: "http://a.b/c"))
    }
}

@MainActor
struct MessageFormatterTests {
    private let formatter = MessageFormatter(
        userName: { ["100": "Alice", "200": "Bob", "300": "Carol"]["\($0)"] ?? "User \($0)" },
        chatTitle: { _ in "Channel" },
        messagePreview: { $0 == 5 ? "Hello there" : nil }
    )

    private func service(_ content: MessageContent, sender: Int64 = 100, channel: Bool = false) -> ChatMessage {
        var message = ChatMessage(Fixtures.message(id: 1, content: content, senderUserId: sender))
        if channel {
            message = ChatMessage(Message(
                authorSignature: "", autoDeleteIn: 0, canBeSaved: true, chatId: 1, chatInstance: 0,
                containsUnreadMention: false, containsUnreadPollVotes: false, content: content, date: 0,
                editDate: 0, effectId: 0, ephemeralContent: nil, ephemeralMessageId: 0, factCheck: nil,
                forwardInfo: nil, guestBotCallerId: nil, hasTimestampedMedia: false, id: 1, importInfo: nil,
                interactionInfo: nil, isChannelPost: true, isFromOffline: false, isOutgoing: false,
                isPaidGramSuggestedPost: false, isPaidStarSuggestedPost: false, isPinned: false, mediaAlbumId: 0,
                paidMessageStarCount: 0, receiverId: nil, replyMarkup: nil, replyTo: nil, restrictionInfo: nil,
                schedulingState: nil, selfDestructIn: 0, selfDestructType: nil, senderBoostCount: 0,
                senderBusinessBotUserId: 0, senderId: .messageSenderChat(MessageSenderChat(chatId: 1)),
                senderTag: "", sendingState: nil, suggestedPostInfo: nil, summaryLanguageCode: "",
                topicId: nil, unreadReactions: [], viaBotUserId: 0
            ))
        }
        return message
    }

    @Test func textPreviewIsSingleLine() {
        #expect(formatter.preview(Fixtures.textContent("Line one\nLine two")) == "Line one Line two")
    }

    @Test func memberJoinAndAdd() {
        let joined = service(.messageChatAddMembers(MessageChatAddMembers(memberUserIds: [100])))
        #expect(formatter.serviceText(for: joined) == "Alice joined the group")

        let added = service(.messageChatAddMembers(MessageChatAddMembers(memberUserIds: [200, 300])))
        #expect(formatter.serviceText(for: added) == "Alice added Bob and Carol")
    }

    @Test func memberLeaveAndRemove() {
        let left = service(.messageChatDeleteMember(MessageChatDeleteMember(userId: 100)))
        #expect(formatter.serviceText(for: left) == "Alice left the group")

        let removed = service(.messageChatDeleteMember(MessageChatDeleteMember(userId: 200)))
        #expect(formatter.serviceText(for: removed) == "Alice removed Bob")
    }

    @Test func titleChangeInGroupAndChannel() {
        let content = MessageContent.messageChatChangeTitle(MessageChatChangeTitle(title: "News"))
        #expect(formatter.serviceText(for: service(content)) == "Alice changed the group name to “News”")
        #expect(formatter.serviceText(for: service(content, channel: true)) == "Channel name changed to “News”")
    }

    @Test func pinnedMessageQuotesPreview() {
        let pinned = service(.messagePinMessage(MessagePinMessage(messageId: 5)))
        #expect(formatter.serviceText(for: pinned) == "Alice pinned “Hello there”")
        let unknown = service(.messagePinMessage(MessagePinMessage(messageId: 6)))
        #expect(formatter.serviceText(for: unknown) == "Alice pinned a message")
    }

    @Test func callDescriptions() {
        let missed = MessageCall(discardReason: .callDiscardReasonMissed, duration: 0, isVideo: false, uniqueId: 0)
        #expect(formatter.callDescription(missed) == "Missed call")
        let finished = MessageCall(discardReason: .callDiscardReasonHungUp, duration: 75, isVideo: true, uniqueId: 0)
        #expect(formatter.callDescription(finished) == "Video call (1:15)")
    }

    @Test func truncation() {
        #expect("abcdef".truncated(to: 3) == "abc…")
        #expect("abc".truncated(to: 3) == "abc")
    }
}

@MainActor
struct DateFormattingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Wednesday, 15 November 2023, 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_700_049_600)

    private var formatting: DateFormatting {
        DateFormatting(now: now, calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
    }

    @Test func daySeparators() {
        #expect(formatting.daySeparator(now.addingTimeInterval(-3600)) == "Today")
        #expect(formatting.daySeparator(now.addingTimeInterval(-86_400)) == "Yesterday")
        #expect(formatting.daySeparator(now.addingTimeInterval(-3 * 86_400)).contains("November 12"))
        #expect(formatting.daySeparator(now.addingTimeInterval(-400 * 86_400)).contains("2022"))
    }

    @Test func chatListTimestamps() {
        #expect(formatting.chatListTimestamp(now.addingTimeInterval(-3600)) == formatting.time(now.addingTimeInterval(-3600)))
        #expect(formatting.chatListTimestamp(now.addingTimeInterval(-2 * 86_400)) == "Mon")
        #expect(formatting.chatListTimestamp(now.addingTimeInterval(-30 * 86_400)).contains("10"))
    }

    @Test func presence() {
        #expect(formatting.presence(.userStatusOnline(UserStatusOnline(expires: 0))) == "online")
        let justNow = UserStatus.userStatusOffline(UserStatusOffline(wasOnline: Int(now.timeIntervalSince1970) - 10))
        #expect(formatting.presence(justNow) == "last seen just now")
        let minutes = UserStatus.userStatusOffline(UserStatusOffline(wasOnline: Int(now.timeIntervalSince1970) - 300))
        #expect(formatting.presence(minutes) == "last seen 5 minutes ago")
        #expect(formatting.presence(.userStatusRecently(UserStatusRecently(byMyPrivacySettings: false))) == "last seen recently")
    }

    @Test func durations() {
        #expect(DurationFormatting.short(5) == "0:05")
        #expect(DurationFormatting.short(65) == "1:05")
        #expect(DurationFormatting.short(3725) == "1:02:05")
        #expect(DurationFormatting.short(-1) == "0:00")
    }
}
