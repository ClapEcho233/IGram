//
//  HistoryLayout.swift
//  IGram
//

import Foundation
@preconcurrency import TDLibKit

/// One row of the history view.
enum HistoryEntry: Identifiable, Equatable {
    /// A floating day header; the date is the start of that day.
    case day(Date)
    /// The "Unread messages" bar above the first unread incoming message.
    case unread
    case message(MessageEntry)

    var id: String {
        switch self {
        case .day(let date): "day-\(Int(date.timeIntervalSince1970))"
        case .unread: "unread"
        case .message(let entry): entry.id
        }
    }
}

/// A message, or several messages of one album, rendered as a single bubble.
struct MessageEntry: Equatable {
    var messages: [ChatMessage]
    /// First bubble of a run by the same sender: shows the sender's name.
    var isFirstInGroup: Bool
    /// Last bubble of a run: shows the avatar and the bubble tail.
    var isLastInGroup: Bool

    var primary: ChatMessage { messages[0] }
    var isAlbum: Bool { messages.count > 1 }

    var id: String {
        let album = primary.mediaAlbumId
        return album != 0 ? "album-\(album)" : HistoryLayout.messageRowId(primary.id)
    }

    /// The message carrying the visible caption: albums show the one caption they have.
    var captionMessage: ChatMessage {
        messages.first { $0.text?.text.isEmpty == false } ?? primary
    }

    func contains(_ messageId: Int64) -> Bool {
        messages.contains { $0.id == messageId }
    }
}

/// Turns loaded messages into rows, after tdesktop's `HistoryView::Element`
/// date and "attach to previous" logic.
enum HistoryLayout {
    /// tdesktop's `kAttachMessageToPreviousSecondsDelta`.
    static let attachWindow = 900

    static func messageRowId(_ messageId: Int64) -> String { "message-\(messageId)" }

    /// The day each row falls on, keyed by row id, following the day headers.
    static func days(of entries: [HistoryEntry]) -> [String: Date] {
        var days: [String: Date] = [:]
        var current: Date?
        for entry in entries {
            if case .day(let date) = entry { current = date }
            if let current { days[entry.id] = current }
        }
        return days
    }

    /// - Parameters:
    ///   - messages: loaded messages in ascending id order.
    ///   - lastReadInboxMessageId: incoming messages after this id get the
    ///     unread bar; pass `nil` to hide it.
    static func entries(
        for messages: [ChatMessage],
        lastReadInboxMessageId: Int64?,
        calendar: Calendar = .current
    ) -> [HistoryEntry] {
        var groups: [[ChatMessage]] = []
        for message in messages {
            if let last = groups.last?.last,
               message.mediaAlbumId != 0,
               message.mediaAlbumId == last.mediaAlbumId {
                groups[groups.count - 1].append(message)
            } else {
                groups.append([message])
            }
        }

        var result: [HistoryEntry] = []
        result.reserveCapacity(groups.count + 8)
        var previousDay: Date?
        var didPlaceUnread = lastReadInboxMessageId == nil

        for (index, group) in groups.enumerated() {
            let first = group[0]
            let day = calendar.startOfDay(for: first.dateValue)
            if day != previousDay {
                result.append(.day(day))
                previousDay = day
            }
            if !didPlaceUnread, let lastRead = lastReadInboxMessageId,
               group.contains(where: { $0.id > lastRead && !$0.isOutgoing }) {
                result.append(.unread)
                didPlaceUnread = true
            }

            let previous = index > 0 ? groups[index - 1].last : nil
            let next = index + 1 < groups.count ? groups[index + 1].first : nil
            let attachedToPrevious = previous.map { attaches(first, to: $0, calendar: calendar) } ?? false
            let attachesNext = next.map { attaches($0, to: group[group.count - 1], calendar: calendar) } ?? false
            // The unread bar breaks a run just like a date header does.
            let unreadBreak = result.last == .unread
            result.append(.message(MessageEntry(
                messages: group,
                isFirstInGroup: !attachedToPrevious || unreadBreak,
                isLastInGroup: !attachesNext
            )))
        }
        return result
    }

    /// Whether `message` continues the bubble run of `previous`.
    static func attaches(_ message: ChatMessage, to previous: ChatMessage, calendar: Calendar = .current) -> Bool {
        guard !message.isService, !previous.isService,
              message.senderId == previous.senderId,
              message.isOutgoing == previous.isOutgoing,
              abs(message.date - previous.date) < attachWindow,
              calendar.isDate(message.dateValue, inSameDayAs: previous.dateValue)
        else { return false }
        return (message.forwardInfo == nil) == (previous.forwardInfo == nil)
    }
}
