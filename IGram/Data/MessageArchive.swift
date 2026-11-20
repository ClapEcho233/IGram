//
//  MessageArchive.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// Keeps what Telegram would otherwise lose, like AyuGram: messages other
/// people delete and earlier versions of edited messages.
///
/// TDLib forgets a message as soon as it reports the deletion, so recent
/// messages of every chat are remembered in memory to match a deletion or an
/// edit to the content it replaces. Kept messages and edits are saved per
/// account and survive restarts.
@Observable
final class MessageArchive {
    /// One earlier version of an edited message.
    struct Edit: Codable, Equatable, Identifiable {
        /// When this version was written (the send or previous edit date).
        let date: Int
        let text: String

        var id: Int { date }
    }

    private(set) var deleted: [Int64: [Int64: ChatMessage]] = [:]
    private(set) var edits: [String: [Edit]] = [:]

    /// Messages remembered per chat, to recover deleted or edited content.
    @ObservationIgnored private var recent: [Int64: [Int64: ChatMessage]] = [:]
    /// Deletions the user made from IGram, which aren't kept.
    @ObservationIgnored private var expectedDeletions: [Int64: Set<Int64>] = [:]
    @ObservationIgnored private var clearedChats: [Int64: Date] = [:]
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let features: ExtraFeatures
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// How many recent messages are remembered per chat.
    static let recentLimit = 500

    init(directory: URL?, features: ExtraFeatures = .shared) {
        self.features = features
        fileURL = directory?.appending(path: "message-archive.json")
        load()
    }

    // MARK: - Queries

    func isDeleted(chatId: Int64, messageId: Int64) -> Bool {
        deleted[chatId]?[messageId] != nil
    }

    func edits(chatId: Int64, messageId: Int64) -> [Edit] {
        edits[Self.key(chatId, messageId)] ?? []
    }

    /// Kept deleted messages of a chat (or forum topic) with ids in `range`.
    func deletedMessages(chatId: Int64, in range: ClosedRange<Int64>, topic: MessageTopic? = nil) -> [ChatMessage] {
        guard let messages = deleted[chatId] else { return [] }
        return messages.values.filter { message in
            range.contains(message.id) && (topic == nil || message.message.topicId == topic)
        }
    }

    var keptMessageCount: Int { deleted.values.reduce(0) { $0 + $1.count } }
    var editedMessageCount: Int { edits.count }

    // MARK: - Recording

    /// Remembers messages loaded or received so a later deletion or edit can
    /// be matched to their content.
    func remember(_ messages: [Message]) {
        guard features.keepDeletedMessages || features.keepEditHistory else { return }
        for message in messages where message.sendingState == nil {
            var chat = recent[message.chatId] ?? [:]
            chat[message.id] = ChatMessage(message)
            if chat.count > Self.recentLimit {
                // Forget the oldest; ids grow over time within a chat.
                let excess = chat.keys.sorted().prefix(chat.count - Self.recentLimit)
                excess.forEach { chat[$0] = nil }
            }
            recent[message.chatId] = chat
        }
    }

    /// Marks deletions the user is about to make, which shouldn't be kept.
    func expectDeletion(chatId: Int64, messageIds: [Int64]) {
        expectedDeletions[chatId, default: []].formUnion(messageIds)
    }

    /// The user is clearing a whole chat; its deletions aren't kept for a while.
    func expectHistoryCleared(chatId: Int64) {
        clearedChats[chatId] = .now
    }

    /// Forgets everything kept so far.
    func clearAll() {
        deleted = [:]
        edits = [:]
        scheduleSave()
    }

    func handle(_ update: Update) {
        switch update {
        case .updateNewMessage(let value):
            remember([value.message])
        case .updateMessageSendSucceeded(let value):
            remember([value.message])
        case .updateMessageContent(let value):
            recordContentChange(chatId: value.chatId, messageId: value.messageId, newContent: value.newContent)
        case .updateMessageEdited(let value):
            recent[value.chatId]?[value.messageId]?.apply(editDate: value.editDate, replyMarkup: value.replyMarkup)
        case .updateDeleteMessages(let value):
            recordDeletion(chatId: value.chatId, messageIds: value.messageIds, isPermanent: value.isPermanent, fromCache: value.fromCache)
        default:
            break
        }
    }

    private func recordContentChange(chatId: Int64, messageId: Int64, newContent: MessageContent) {
        guard let old = recent[chatId]?[messageId] else { return }
        recent[chatId]?[messageId]?.apply(content: newContent)
        guard features.keepEditHistory,
              let oldText = old.text?.text,
              let newText = newContent.formattedText?.text,
              oldText != newText
        else { return }
        let version = Edit(date: old.editDate != 0 ? old.editDate : old.date, text: oldText)
        let key = Self.key(chatId, messageId)
        var versions = edits[key] ?? []
        guard !versions.contains(version) else { return }
        versions.append(version)
        edits[key] = versions
        scheduleSave()
    }

    private func recordDeletion(chatId: Int64, messageIds: [Int64], isPermanent: Bool, fromCache: Bool) {
        let expected = expectedDeletions[chatId] ?? []
        expectedDeletions[chatId] = expected.subtracting(messageIds)
        defer { messageIds.forEach { recent[chatId]?[$0] = nil } }
        guard features.keepDeletedMessages, isPermanent, !fromCache else { return }
        if let cleared = clearedChats[chatId], Date.now.timeIntervalSince(cleared) < 60 { return }
        var kept = deleted[chatId] ?? [:]
        for id in messageIds where !expected.contains(id) {
            guard let message = recent[chatId]?[id], !message.isService else { continue }
            kept[id] = message
        }
        guard kept.count != (deleted[chatId]?.count ?? 0) else { return }
        deleted[chatId] = kept
        scheduleSave()
    }

    // MARK: - Persistence

    /// A kept message as saved: TDLib's message plus the fields edits changed.
    private struct KeptMessage: Codable {
        let message: Message
        let content: MessageContent
        let editDate: Int

        init(_ message: ChatMessage) {
            self.message = message.message
            content = message.content
            editDate = message.editDate
        }

        var chatMessage: ChatMessage {
            var result = ChatMessage(message)
            result.apply(content: content)
            result.apply(editDate: editDate, replyMarkup: message.replyMarkup)
            return result
        }
    }

    private struct Snapshot: Codable {
        var deleted: [String: [KeptMessage]]
        var edits: [String: [Edit]]
    }

    private static func key(_ chatId: Int64, _ messageId: Int64) -> String { "\(chatId):\(messageId)" }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            for (chat, messages) in snapshot.deleted {
                guard let chatId = Int64(chat) else { continue }
                deleted[chatId] = Dictionary(messages.map { ($0.message.id, $0.chatMessage) }, uniquingKeysWith: { $1 })
            }
            edits = snapshot.edits
        } catch {
            Log.data.error("Couldn't read the message archive: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSave() {
        guard let fileURL else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            let snapshot = Snapshot(
                deleted: Dictionary(uniqueKeysWithValues: deleted.map { (String($0.key), $0.value.values.map(KeptMessage.init)) }),
                edits: edits
            )
            do {
                let data = try JSONEncoder().encode(snapshot)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Log.data.error("Couldn't save the message archive: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Writes pending changes now, e.g. before quitting or in tests.
    func saveNow() async {
        await saveTask?.value
    }
}
