//
//  HistoryModel.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// The loaded slice of one chat's history, kept in ascending id order.
///
/// Plays the role of tdesktop's `History` blocks: it pages older and newer
/// messages through `getChatHistory`, can jump into the middle of the history
/// (leaving a gap to the newest messages), and applies live message updates.
@Observable
final class HistoryModel {
    let chatId: Int64

    private(set) var messages: [ChatMessage] = []
    private(set) var didLoadInitial = false
    private(set) var isLoadingOlder = false
    private(set) var isLoadingNewer = false
    private(set) var hasMoreOlder = true
    /// True when the loaded slice does not reach the newest message.
    private(set) var hasMoreNewer = false
    /// Message the view should scroll to, set after jumps.
    private(set) var focusRequest: FocusRequest?
    /// Messages that loaded messages reply to, when outside the loaded slice.
    private(set) var replyCache: [Int64: ChatMessage] = [:]
    /// What the user may do with each message (edit, delete, forward…).
    private(set) var properties: [Int64: MessageProperties] = [:]

    struct FocusRequest: Equatable {
        let messageId: Int64
        let highlight: Bool
        let token = UUID()
    }

    @ObservationIgnored private let client: TelegramClient
    @ObservationIgnored private var requestedReplies: Set<Int64> = []
    @ObservationIgnored private var pendingViews: Set<Int64> = []
    @ObservationIgnored private var viewFlushTask: Task<Void, Never>?
    @ObservationIgnored private var isOpen = false

    static let pageSize = 50

    init(chatId: Int64, client: TelegramClient) {
        self.chatId = chatId
        self.client = client
    }

    // MARK: - Lifecycle

    /// Tells TDLib the chat is visible and loads the first page.
    ///
    /// - Parameter lastReadInboxMessageId: when there are unread messages, the
    ///   history opens around the first unread one, like tdesktop does.
    func open(unreadCount: Int, lastReadInboxMessageId: Int64) async {
        guard !isOpen else { return }
        isOpen = true
        let chatId = chatId
        _ = try? await client.api.openChat(chatId: chatId)
        guard !didLoadInitial else { return }
        if unreadCount > 0, lastReadInboxMessageId > 0 {
            await load(around: lastReadInboxMessageId, highlight: false)
        } else {
            await loadLatest()
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        flushViews()
        let chatId = chatId
        let api = client.api
        Task { _ = try? await api.closeChat(chatId: chatId) }
    }

    // MARK: - Paging

    /// Replaces the slice with the newest messages.
    func loadLatest() async {
        var collected: [Message] = []
        var fromId: Int64 = 0
        // TDLib may answer the first request from its cache with very few
        // messages, so keep asking until a page is filled or history ends.
        var reachedEnd = false
        for _ in 0..<4 where collected.count < Self.pageSize {
            guard let batch = await fetch(from: fromId, offset: 0, limit: Self.pageSize - collected.count) else { return }
            guard let oldest = batch.last else { reachedEnd = true; break }
            collected += batch
            fromId = oldest.id
        }
        setSlice(collected, hasMoreOlder: !reachedEnd, hasMoreNewer: false)
        if let last = messages.last {
            focusRequest = FocusRequest(messageId: last.id, highlight: false)
        }
    }

    /// Replaces the slice with messages around `messageId` and focuses it.
    func load(around messageId: Int64, highlight: Bool = true) async {
        let half = Self.pageSize / 2
        guard let batch = await fetch(from: messageId, offset: -half, limit: Self.pageSize) else { return }
        guard !batch.isEmpty else {
            await loadLatest()
            return
        }
        let newerCount = batch.filter { $0.id > messageId }.count
        setSlice(batch, hasMoreOlder: true, hasMoreNewer: newerCount >= half - 1)
        let target = messages.first { $0.id > messageId && !highlight } ?? messages.first { $0.id >= messageId }
        focusRequest = FocusRequest(messageId: target?.id ?? messageId, highlight: highlight)
    }

    /// Scrolls to a message, loading its surroundings if needed.
    func jump(to messageId: Int64) async {
        if messages.contains(where: { $0.id == messageId }) {
            focusRequest = FocusRequest(messageId: messageId, highlight: true)
        } else {
            await load(around: messageId)
        }
    }

    /// Scrolls to the newest message, reloading when the slice has a gap.
    func jumpToLatest() async {
        if hasMoreNewer {
            await loadLatest()
        } else if let last = messages.last {
            focusRequest = FocusRequest(messageId: last.id, highlight: false)
        }
    }

    func loadOlder() async {
        guard didLoadInitial, hasMoreOlder, !isLoadingOlder, let oldest = messages.first else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        guard let batch = await fetch(from: oldest.id, offset: 0, limit: Self.pageSize) else { return }
        let older = batch.filter { $0.id < oldest.id }
        if older.isEmpty {
            hasMoreOlder = false
        } else {
            messages = Self.merge(messages, older)
        }
    }

    func loadNewer() async {
        guard didLoadInitial, hasMoreNewer, !isLoadingNewer, let newest = messages.last else { return }
        isLoadingNewer = true
        defer { isLoadingNewer = false }
        guard let batch = await fetch(from: newest.id, offset: -(Self.pageSize - 1), limit: Self.pageSize) else { return }
        let newer = batch.filter { $0.id > newest.id }
        if newer.isEmpty {
            hasMoreNewer = false
        } else {
            messages = Self.merge(messages, newer)
        }
    }

    /// Replaces the loaded slice with `batch` (in any order).
    func setSlice(_ batch: [Message], hasMoreOlder: Bool, hasMoreNewer: Bool) {
        messages = Self.merge([], batch)
        self.hasMoreOlder = hasMoreOlder
        self.hasMoreNewer = hasMoreNewer
        didLoadInitial = true
    }

    private func fetch(from messageId: Int64, offset: Int, limit: Int) async -> [Message]? {
        do {
            let result = try await client.api.getChatHistory(
                chatId: chatId,
                fromMessageId: messageId,
                limit: limit,
                offset: offset,
                onlyLocal: false
            )
            return result.messages ?? []
        } catch {
            Log.data.error("getChatHistory failed: \(error.telegramMessage, privacy: .public)")
            return nil
        }
    }

    /// Merges `incoming` into `existing`, de-duplicating by id and sorting ascending.
    static func merge(_ existing: [ChatMessage], _ incoming: [Message]) -> [ChatMessage] {
        var byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for message in incoming where byId[message.id] == nil {
            byId[message.id] = ChatMessage(message)
        }
        return byId.values.sorted { $0.id < $1.id }
    }

    // MARK: - Lookups

    func message(_ id: Int64) -> ChatMessage? {
        guard let index = index(of: id) else { return replyCache[id] }
        return messages[index]
    }

    /// The message `message` replies to, fetching it in the background if needed.
    func repliedMessage(for message: ChatMessage) -> ChatMessage? {
        guard case .messageReplyToMessage(let reply) = message.replyTo, reply.messageId != 0 else { return nil }
        if reply.chatId == chatId, let index = index(of: reply.messageId) {
            return messages[index]
        }
        if let cached = replyCache[reply.messageId] { return cached }
        requestReply(for: message, replyId: reply.messageId)
        return nil
    }

    private func requestReply(for message: ChatMessage, replyId: Int64) {
        guard !requestedReplies.contains(replyId) else { return }
        requestedReplies.insert(replyId)
        let chatId = chatId
        let messageId = message.id
        let api = client.api
        Task {
            guard let replied = try? await api.getRepliedMessage(chatId: chatId, messageId: messageId) else { return }
            self.replyCache[replyId] = ChatMessage(replied)
        }
    }

    private func index(of id: Int64) -> Int? {
        var low = 0
        var high = messages.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let midId = messages[mid].id
            if midId == id { return mid }
            if midId < id { low = mid + 1 } else { high = mid - 1 }
        }
        // Pending messages can transiently break ordering; fall back to a scan.
        return messages.lastIndex { $0.id == id }
    }

    // MARK: - Message properties

    /// Loads permissions for context menus. `getMessageProperties` is an
    /// offline request, so prefetching visible messages is cheap.
    func loadProperties(for messageIds: [Int64]) async {
        for id in messageIds where properties[id] == nil {
            if let value = try? await client.api.getMessageProperties(chatId: chatId, messageId: id) {
                properties[id] = value
            }
        }
    }

    // MARK: - Read state

    /// Marks messages as viewed; batched to avoid a request per row.
    func markViewed(_ messageId: Int64) {
        guard isOpen else { return }
        pendingViews.insert(messageId)
        guard viewFlushTask == nil else { return }
        viewFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.flushViews()
        }
    }

    private func flushViews() {
        viewFlushTask?.cancel()
        viewFlushTask = nil
        guard !pendingViews.isEmpty else { return }
        let ids = pendingViews.sorted()
        pendingViews.removeAll()
        let chatId = chatId
        let api = client.api
        Task {
            _ = try? await api.viewMessages(
                chatId: chatId,
                forceRead: true,
                messageIds: ids,
                source: .messageSourceChatHistory
            )
        }
    }

    // MARK: - Updates

    func handle(_ update: Update) {
        switch update {
        case .updateNewMessage(let value):
            insertLive(value.message)
        case .updateMessageSendSucceeded(let value):
            replace(value.oldMessageId, with: value.message)
        case .updateMessageSendFailed(let value):
            replace(value.oldMessageId, with: value.message)
        case .updateMessageContent(let value):
            mutate(value.messageId) { $0.apply(content: value.newContent) }
        case .updateMessageEdited(let value):
            properties[value.messageId] = nil
            mutate(value.messageId) { $0.apply(editDate: value.editDate) }
        case .updateMessageInteractionInfo(let value):
            mutate(value.messageId) { $0.apply(interactionInfo: value.interactionInfo) }
        case .updateMessageIsPinned(let value):
            mutate(value.messageId) { $0.apply(isPinned: value.isPinned) }
        case .updateMessageMentionRead(let value):
            mutate(value.messageId) { $0.markMentionRead() }
        case .updateMessageContentOpened(let value):
            mutate(value.messageId) { $0.markContentOpened() }
        case .updateDeleteMessages(let value):
            guard !value.fromCache else { break }
            let ids = Set(value.messageIds)
            messages.removeAll { ids.contains($0.id) }
        default:
            break
        }
    }

    private func insertLive(_ message: Message) {
        // While the slice has a gap to the newest messages, new ones would be
        // disconnected from what is loaded; the view offers a jump instead.
        guard didLoadInitial, !hasMoreNewer, index(of: message.id) == nil else { return }
        messages = Self.merge(messages, [message])
        if message.isOutgoing {
            focusRequest = FocusRequest(messageId: message.id, highlight: false)
        }
    }

    private func replace(_ oldId: Int64, with message: Message) {
        properties[oldId] = nil
        guard let index = index(of: oldId) else { return }
        messages.remove(at: index)
        messages = Self.merge(messages, [message])
    }

    private func mutate(_ id: Int64, _ change: (inout ChatMessage) -> Void) {
        if let index = index(of: id) {
            change(&messages[index])
        }
        if replyCache[id] != nil {
            change(&replyCache[id]!)
        }
    }
}

extension Update {
    /// The chat a message-level update belongs to, used to route it to an open history.
    var messageChatId: Int64? {
        switch self {
        case .updateNewMessage(let value): value.message.chatId
        case .updateMessageSendSucceeded(let value): value.message.chatId
        case .updateMessageSendFailed(let value): value.message.chatId
        case .updateMessageContent(let value): value.chatId
        case .updateMessageEdited(let value): value.chatId
        case .updateMessageInteractionInfo(let value): value.chatId
        case .updateMessageIsPinned(let value): value.chatId
        case .updateMessageMentionRead(let value): value.chatId
        case .updateMessageContentOpened(let value): value.chatId
        case .updateDeleteMessages(let value): value.chatId
        default: nil
        }
    }
}
