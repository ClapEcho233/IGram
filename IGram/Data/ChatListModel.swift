//
//  ChatListModel.swift
//  IGram
//

import Foundation
import Observation
@preconcurrency import TDLibKit

/// The ordered chats of one chat list (main, archive or a folder).
///
/// Mirrors tdesktop's `Dialogs::IndexedList`. TDLib orders chats by the pair
/// `(position.order, chat.id)` in descending order; pinned chats already carry
/// the highest orders. Positions are applied incrementally with a binary
/// insertion so floods of updates at start-up stay cheap.
@Observable
final class ChatListModel {
    let list: ChatList

    private(set) var chatIds: [Int64] = []
    private(set) var pinnedChatIds: Set<Int64> = []
    private(set) var isLoading = false
    /// Becomes true once TDLib reports that every chat of the list was loaded.
    private(set) var isComplete = false

    private(set) var unreadMessageCount = 0
    private(set) var unreadUnmutedMessageCount = 0
    private(set) var unreadChatCount = 0
    private(set) var unreadUnmutedChatCount = 0

    @ObservationIgnored private var orders: [Int64: Int64] = [:]

    init(list: ChatList) {
        self.list = list
    }

    /// Inserts, moves or removes (`order == 0`) a chat.
    func setPosition(chatId: Int64, order: Int64, isPinned: Bool) {
        let previous = orders[chatId]
        if order == 0 {
            guard previous != nil else { return }
            orders[chatId] = nil
            pinnedChatIds.remove(chatId)
            if let index = chatIds.firstIndex(of: chatId) { chatIds.remove(at: index) }
            return
        }

        if isPinned != pinnedChatIds.contains(chatId) {
            if isPinned { pinnedChatIds.insert(chatId) } else { pinnedChatIds.remove(chatId) }
        }
        guard previous != order else { return }

        var ids = chatIds
        if previous != nil, let index = ids.firstIndex(of: chatId) {
            ids.remove(at: index)
        }
        orders[chatId] = order
        ids.insert(chatId, at: insertionIndex(in: ids, order: order, chatId: chatId))
        chatIds = ids
    }

    func contains(_ chatId: Int64) -> Bool { orders[chatId] != nil }

    func setLoading(_ loading: Bool) { isLoading = loading }
    func markComplete() { isComplete = true }

    func setUnreadMessageCount(total: Int, unmuted: Int) {
        unreadMessageCount = total
        unreadUnmutedMessageCount = unmuted
    }

    func setUnreadChatCount(total: Int, unmuted: Int) {
        unreadChatCount = total
        unreadUnmutedChatCount = unmuted
    }

    /// Whether `a` sorts before `b`: higher order first, then higher chat id.
    static func precedes(_ a: (order: Int64, id: Int64), _ b: (order: Int64, id: Int64)) -> Bool {
        a.order != b.order ? a.order > b.order : a.id > b.id
    }

    private func insertionIndex(in ids: [Int64], order: Int64, chatId: Int64) -> Int {
        var low = 0
        var high = ids.count
        while low < high {
            let mid = (low + high) / 2
            let other = ids[mid]
            if Self.precedes((orders[other] ?? 0, other), (order, chatId)) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}

extension ChatList {
    /// The folder id for `chatListFolder`, otherwise `nil`.
    var folderId: Int? {
        if case .chatListFolder(let folder) = self { return folder.chatFolderId }
        return nil
    }
}
