//
//  MessageArchiveTests.swift
//  IGramTests
//

import Foundation
import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct MessageArchiveTests {
    private static let client = TelegramClient(logVerbosity: 0)

    private func features(keepDeleted: Bool = true, keepEdits: Bool = true) -> ExtraFeatures {
        let defaults = UserDefaults(suiteName: "MessageArchiveTests-\(UUID().uuidString)")!
        let features = ExtraFeatures(defaults: defaults)
        features.keepDeletedMessages = keepDeleted
        features.keepEditHistory = keepEdits
        return features
    }

    private func delete(_ ids: [Int64], chatId: Int64 = 1, permanent: Bool = true, fromCache: Bool = false) -> Update {
        .updateDeleteMessages(UpdateDeleteMessages(chatId: chatId, fromCache: fromCache, isPermanent: permanent, messageIds: ids))
    }

    private func edit(_ id: Int64, to text: String, chatId: Int64 = 1) -> Update {
        .updateMessageContent(UpdateMessageContent(chatId: chatId, messageId: id, newContent: Fixtures.textContent(text)))
    }

    @Test func keepsMessagesOthersDelete() {
        let archive = MessageArchive(directory: nil, features: features())
        archive.handle(.updateNewMessage(UpdateNewMessage(message: Fixtures.message(id: 10))))
        archive.remember([Fixtures.message(id: 20)])
        archive.handle(delete([10, 20, 30]))
        #expect(archive.isDeleted(chatId: 1, messageId: 10))
        #expect(archive.isDeleted(chatId: 1, messageId: 20))
        // Never seen, so there is nothing to keep.
        #expect(!archive.isDeleted(chatId: 1, messageId: 30))
        #expect(archive.deletedMessages(chatId: 1, in: 15...25).map(\.id) == [20])
        #expect(archive.keptMessageCount == 2)
    }

    @Test func ignoresOwnCacheAndTemporaryDeletions() {
        let archive = MessageArchive(directory: nil, features: features())
        archive.remember([10, 20, 30].map { Fixtures.message(id: $0) })
        archive.expectDeletion(chatId: 1, messageIds: [10])
        archive.handle(delete([10]))
        archive.handle(delete([20], fromCache: true))
        archive.handle(delete([30], permanent: false))
        #expect(archive.keptMessageCount == 0)
    }

    @Test func ignoresChatsTheUserClears() {
        let archive = MessageArchive(directory: nil, features: features())
        archive.remember([Fixtures.message(id: 10)])
        archive.expectHistoryCleared(chatId: 1)
        archive.handle(delete([10]))
        #expect(!archive.isDeleted(chatId: 1, messageId: 10))
    }

    @Test func keepsNothingWhenTurnedOff() {
        let archive = MessageArchive(directory: nil, features: features(keepDeleted: false, keepEdits: false))
        archive.remember([Fixtures.message(id: 10)])
        archive.handle(edit(10, to: "changed"))
        archive.handle(delete([10]))
        #expect(archive.keptMessageCount == 0)
        #expect(archive.edits(chatId: 1, messageId: 10).isEmpty)
    }

    @Test func recordsEarlierVersionsOfEdits() {
        let archive = MessageArchive(directory: nil, features: features())
        archive.remember([Fixtures.message(id: 10, content: Fixtures.textContent("first"))])
        archive.handle(edit(10, to: "second"))
        archive.handle(edit(10, to: "second"))
        archive.handle(edit(10, to: "third"))
        #expect(archive.edits(chatId: 1, messageId: 10).map(\.text) == ["first", "second"])
        // A deleted edited message keeps its latest content.
        archive.handle(delete([10]))
        #expect(archive.deletedMessages(chatId: 1, in: 10...10).first?.text?.text == "third")
    }

    @Test func persistsAcrossLaunches() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "archive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let features = features()
        let archive = MessageArchive(directory: directory, features: features)
        archive.remember([Fixtures.message(id: 10, content: Fixtures.textContent("hello"))])
        archive.handle(edit(10, to: "hello there"))
        archive.handle(delete([10]))
        await archive.saveNow()

        let reopened = MessageArchive(directory: directory, features: features)
        #expect(reopened.isDeleted(chatId: 1, messageId: 10))
        #expect(reopened.deletedMessages(chatId: 1, in: 1...100).first?.text?.text == "hello there")
        #expect(reopened.edits(chatId: 1, messageId: 10).map(\.text) == ["hello"])
    }

    @Test func historyKeepsDeletedMessagesAndRestoresThemOnReload() {
        let archive = MessageArchive(directory: nil, features: features())
        let model = HistoryModel(chatId: 1, client: Self.client, archive: archive)
        let messages = [10, 20, 30].map { Fixtures.message(id: $0) }
        archive.remember(messages)
        model.setSlice(messages, hasMoreOlder: false, hasMoreNewer: false)

        let update = delete([20])
        archive.handle(update)
        model.handle(update)
        #expect(model.messages.map(\.id) == [10, 20, 30])

        // TDLib no longer returns it, but reopening the chat brings it back.
        let fresh = HistoryModel(chatId: 1, client: Self.client, archive: archive)
        fresh.setSlice([10, 30].map { Fixtures.message(id: $0) }, hasMoreOlder: false, hasMoreNewer: false)
        #expect(fresh.messages.map(\.id) == [10, 20, 30])
    }

    @Test func historyStillRemovesMessagesNotKept() {
        let archive = MessageArchive(directory: nil, features: features(keepDeleted: false))
        let model = HistoryModel(chatId: 1, client: Self.client, archive: archive)
        model.setSlice([10, 20].map { Fixtures.message(id: $0) }, hasMoreOlder: false, hasMoreNewer: false)
        let update = delete([20])
        archive.handle(update)
        model.handle(update)
        #expect(model.messages.map(\.id) == [10])
    }
}
