//
//  ChatMessage.swift
//  IGram
//

import Foundation
@preconcurrency import TDLibKit

/// A message plus the fields TDLib changes after delivery.
///
/// TDLib's generated `Message` is immutable, while updates such as
/// `updateMessageContent` or `updateMessageInteractionInfo` patch single fields.
/// This wrapper keeps the original snapshot and overlays the patched values,
/// similar to how tdesktop's `HistoryItem` mutates in place.
struct ChatMessage: Identifiable, Equatable {
    let message: Message
    private(set) var content: MessageContent
    private(set) var editDate: Int
    private(set) var interactionInfo: MessageInteractionInfo?
    private(set) var isPinned: Bool
    private(set) var containsUnreadMention: Bool
    private(set) var replyMarkup: ReplyMarkup?

    init(_ message: Message) {
        self.message = message
        content = message.content
        editDate = message.editDate
        interactionInfo = message.interactionInfo
        isPinned = message.isPinned
        containsUnreadMention = message.containsUnreadMention
        replyMarkup = message.replyMarkup
    }

    var id: Int64 { message.id }
    var chatId: Int64 { message.chatId }
    var date: Int { message.date }
    var senderId: MessageSender { message.senderId }
    var isOutgoing: Bool { message.isOutgoing }
    var isChannelPost: Bool { message.isChannelPost }
    var replyTo: MessageReplyTo? { message.replyTo }
    var forwardInfo: MessageForwardInfo? { message.forwardInfo }
    var sendingState: MessageSendingState? { message.sendingState }
    var authorSignature: String { message.authorSignature }
    var viaBotUserId: Int64 { message.viaBotUserId }
    var mediaAlbumId: Int64 { message.mediaAlbumId.rawValue }
    var canBeSaved: Bool { message.canBeSaved }
    var isEdited: Bool { editDate > 0 }

    var dateValue: Date { Date(timeIntervalSince1970: TimeInterval(date)) }

    var isSending: Bool {
        if case .messageSendingStatePending = sendingState { return true }
        return false
    }

    var isFailed: Bool {
        if case .messageSendingStateFailed = sendingState { return true }
        return false
    }

    var isService: Bool { content.isService }

    /// The text or caption, if the content has one.
    var text: FormattedText? { content.formattedText }

    mutating func apply(content: MessageContent) { self.content = content }
    mutating func apply(editDate: Int, replyMarkup: ReplyMarkup?) {
        self.editDate = editDate
        self.replyMarkup = replyMarkup
    }
    mutating func apply(interactionInfo: MessageInteractionInfo?) { self.interactionInfo = interactionInfo }
    mutating func apply(isPinned: Bool) { self.isPinned = isPinned }
    mutating func markMentionRead() { containsUnreadMention = false }

    /// Applies `updateMessageContentOpened`: voice and video notes become listened/viewed.
    mutating func markContentOpened() {
        switch content {
        case .messageVoiceNote(let value):
            content = .messageVoiceNote(MessageVoiceNote(caption: value.caption, isListened: true, voiceNote: value.voiceNote))
        case .messageVideoNote(let value):
            content = .messageVideoNote(MessageVideoNote(isSecret: value.isSecret, isViewed: true, videoNote: value.videoNote))
        default:
            break
        }
    }
}

extension MessageContent {
    /// The text of a text message or the caption of a media message.
    var formattedText: FormattedText? {
        switch self {
        case .messageText(let value): value.text
        case .messagePhoto(let value): value.caption
        case .messageVideo(let value): value.caption
        case .messageAnimation(let value): value.caption
        case .messageDocument(let value): value.caption
        case .messageAudio(let value): value.caption
        case .messageVoiceNote(let value): value.caption
        default: nil
        }
    }

    /// Whether the content renders as a centered service notice rather than a bubble.
    var isService: Bool {
        switch self {
        case .messageText, .messageRichMessage, .messageAnimation, .messageAudio, .messageDocument,
             .messagePaidMedia, .messagePhoto, .messageSticker, .messageVideo, .messageVideoNote,
             .messageVoiceNote, .messageExpiredPhoto, .messageExpiredVideo, .messageExpiredVideoNote,
             .messageExpiredVoiceNote, .messageLiveLocation, .messageLocation, .messageVenue,
             .messageContact, .messageAnimatedEmoji, .messageDice, .messageGame, .messagePoll,
             .messageStakeDice, .messageStory, .messageWidget, .messageChecklist, .messageInvoice,
             .messageCall, .messageGiveaway, .messageUnsupported:
            false
        default:
            true
        }
    }
}

extension MessageSender {
    var userId: Int64? {
        if case .messageSenderUser(let value) = self { return value.userId }
        return nil
    }

    var chatId: Int64? {
        if case .messageSenderChat(let value) = self { return value.chatId }
        return nil
    }
}
