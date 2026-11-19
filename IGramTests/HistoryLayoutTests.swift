//
//  HistoryLayoutTests.swift
//  IGramTests
//

import Foundation
import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct HistoryLayoutTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 15 November 2023, 10:00 UTC.
    private let base = 1_700_042_400

    private func message(
        _ id: Int64,
        at offset: Int = 0,
        sender: Int64 = 100,
        outgoing: Bool = false,
        album: Int64 = 0,
        content: MessageContent? = nil
    ) -> ChatMessage {
        ChatMessage(Fixtures.message(
            id: id,
            content: content,
            date: base + offset,
            senderUserId: sender,
            isOutgoing: outgoing,
            mediaAlbumId: album
        ))
    }

    private func layout(_ messages: [ChatMessage], lastRead: Int64? = nil) -> [HistoryEntry] {
        HistoryLayout.entries(for: messages, lastReadInboxMessageId: lastRead, calendar: calendar)
    }

    private func messageEntries(_ entries: [HistoryEntry]) -> [MessageEntry] {
        entries.compactMap { if case .message(let entry) = $0 { entry } else { nil } }
    }

    @Test func startsWithDayHeader() {
        let entries = layout([message(1)])
        #expect(entries.count == 2)
        #expect(entries.first == .day(calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(base)))))
    }

    @Test func newDayGetsHeader() {
        let entries = layout([message(1), message(2, at: 86_400)])
        #expect(entries.filter { if case .day = $0 { true } else { false } }.count == 2)
        let bubbles = messageEntries(entries)
        #expect(bubbles.allSatisfy { $0.isFirstInGroup && $0.isLastInGroup })
    }

    @Test func groupsConsecutiveMessagesBySameSender() {
        let bubbles = messageEntries(layout([message(1), message(2, at: 60), message(3, at: 120)]))
        #expect(bubbles.map(\.isFirstInGroup) == [true, false, false])
        #expect(bubbles.map(\.isLastInGroup) == [false, false, true])
    }

    @Test func breaksGroupOnDifferentSenderOrLongPause() {
        let bubbles = messageEntries(layout([
            message(1),
            message(2, at: 60, sender: 200),
            message(3, at: 60 + HistoryLayout.attachWindow, sender: 200),
        ]))
        #expect(bubbles.map(\.isFirstInGroup) == [true, true, true])
    }

    @Test func serviceMessagesNeverAttach() {
        let service = MessageContent.messageChatChangeTitle(MessageChatChangeTitle(title: "T"))
        let bubbles = messageEntries(layout([message(1), message(2, at: 10, content: service), message(3, at: 20)]))
        #expect(bubbles.map(\.isFirstInGroup) == [true, true, true])
    }

    @Test func mergesAlbums() {
        let bubbles = messageEntries(layout([message(1, album: 77), message(2, album: 77), message(3, at: 30)]))
        #expect(bubbles.count == 2)
        #expect(bubbles[0].isAlbum)
        #expect(bubbles[0].id == "album-77")
        #expect(bubbles[1].id == HistoryLayout.messageRowId(3))
    }

    @Test func placesUnreadBarBeforeFirstUnreadIncoming() {
        let entries = layout([message(1), message(2, outgoing: true), message(3, at: 30), message(4, at: 40)], lastRead: 2)
        let index = entries.firstIndex(of: .unread)
        #expect(index != nil)
        if let index, case .message(let next) = entries[index + 1] {
            #expect(next.primary.id == 3)
            #expect(next.isFirstInGroup)
        }
    }

    @Test func noUnreadBarWhenEverythingIsRead() {
        #expect(!layout([message(1), message(2)], lastRead: 2).contains(.unread))
        #expect(!layout([message(1)], lastRead: nil).contains(.unread))
    }

    @Test func captionMessageInAlbum() {
        let photo = Fixtures.textContent("")
        let captioned = Fixtures.textContent("Look")
        let entry = MessageEntry(
            messages: [message(1, content: photo), message(2, content: captioned)],
            isFirstInGroup: true,
            isLastInGroup: true
        )
        #expect(entry.captionMessage.id == 2)
        #expect(entry.contains(2))
        #expect(!entry.contains(3))
    }
}
