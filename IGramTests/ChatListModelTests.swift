//
//  ChatListModelTests.swift
//  IGramTests
//

import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct ChatListModelTests {
    private func makeModel() -> ChatListModel { ChatListModel(list: .chatListMain) }

    @Test func sortsByOrderDescending() {
        let model = makeModel()
        model.setPosition(chatId: 1, order: 10, isPinned: false)
        model.setPosition(chatId: 2, order: 30, isPinned: false)
        model.setPosition(chatId: 3, order: 20, isPinned: false)
        #expect(model.chatIds == [2, 3, 1])
    }

    @Test func breaksTiesByChatIdDescending() {
        let model = makeModel()
        model.setPosition(chatId: 5, order: 10, isPinned: false)
        model.setPosition(chatId: 9, order: 10, isPinned: false)
        model.setPosition(chatId: 7, order: 10, isPinned: false)
        #expect(model.chatIds == [9, 7, 5])
    }

    @Test func movesChatWhenOrderChanges() {
        let model = makeModel()
        model.setPosition(chatId: 1, order: 10, isPinned: false)
        model.setPosition(chatId: 2, order: 20, isPinned: false)
        model.setPosition(chatId: 1, order: 30, isPinned: false)
        #expect(model.chatIds == [1, 2])
    }

    @Test func zeroOrderRemovesChat() {
        let model = makeModel()
        model.setPosition(chatId: 1, order: 10, isPinned: true)
        model.setPosition(chatId: 2, order: 20, isPinned: false)
        model.setPosition(chatId: 1, order: 0, isPinned: false)
        #expect(model.chatIds == [2])
        #expect(!model.contains(1))
        #expect(model.pinnedChatIds.isEmpty)
    }

    @Test func removingUnknownChatIsNoOp() {
        let model = makeModel()
        model.setPosition(chatId: 1, order: 10, isPinned: false)
        model.setPosition(chatId: 99, order: 0, isPinned: false)
        #expect(model.chatIds == [1])
    }

    @Test func tracksPinnedChats() {
        let model = makeModel()
        model.setPosition(chatId: 1, order: 100, isPinned: true)
        model.setPosition(chatId: 2, order: 10, isPinned: false)
        #expect(model.pinnedChatIds == [1])
        model.setPosition(chatId: 1, order: 100, isPinned: false)
        #expect(model.pinnedChatIds.isEmpty)
        #expect(model.chatIds == [1, 2])
    }

    @Test func staysSortedUnderManyUpdates() {
        let model = makeModel()
        var expected: [Int64: Int64] = [:]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let chatId = Int64.random(in: 1...60, using: &generator)
            let order = Int64.random(in: 0...40, using: &generator)
            model.setPosition(chatId: chatId, order: order, isPinned: false)
            expected[chatId] = order == 0 ? nil : order
        }
        let sorted = expected.sorted { ChatListModel.precedes(($0.value, $0.key), ($1.value, $1.key)) }.map(\.key)
        #expect(model.chatIds == sorted)
    }

    @Test func folderIdExtraction() {
        #expect(ChatList.chatListFolder(ChatListFolder(chatFolderId: 4)).folderId == 4)
        #expect(ChatList.chatListMain.folderId == nil)
    }
}
