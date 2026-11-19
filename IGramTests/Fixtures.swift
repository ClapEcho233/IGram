//
//  Fixtures.swift
//  IGramTests
//

import Foundation
@preconcurrency import TDLibKit
@testable import IGram

/// Builders for TDLib values whose generated initializers take every field.
enum Fixtures {
    static func text(_ string: String, entities: [TextEntity] = []) -> FormattedText {
        FormattedText(entities: entities, text: string)
    }

    static func textContent(_ string: String, entities: [TextEntity] = []) -> MessageContent {
        .messageText(MessageText(linkPreview: nil, linkPreviewOptions: nil, text: text(string, entities: entities)))
    }

    static func message(
        id: Int64,
        chatId: Int64 = 1,
        content: MessageContent? = nil,
        date: Int = 1_700_000_000,
        senderUserId: Int64 = 100,
        isOutgoing: Bool = false,
        mediaAlbumId: Int64 = 0,
        replyTo: MessageReplyTo? = nil,
        sendingState: MessageSendingState? = nil
    ) -> Message {
        Message(
            authorSignature: "",
            autoDeleteIn: 0,
            canBeSaved: true,
            chatId: chatId,
            chatInstance: 0,
            containsUnreadMention: false,
            containsUnreadPollVotes: false,
            content: content ?? textContent("Message \(id)"),
            date: date,
            editDate: 0,
            effectId: 0,
            ephemeralContent: nil,
            ephemeralMessageId: 0,
            factCheck: nil,
            forwardInfo: nil,
            guestBotCallerId: nil,
            hasTimestampedMedia: false,
            id: id,
            importInfo: nil,
            interactionInfo: nil,
            isChannelPost: false,
            isFromOffline: false,
            isOutgoing: isOutgoing,
            isPaidGramSuggestedPost: false,
            isPaidStarSuggestedPost: false,
            isPinned: false,
            mediaAlbumId: TdInt64(mediaAlbumId),
            paidMessageStarCount: 0,
            receiverId: nil,
            replyMarkup: nil,
            replyTo: replyTo,
            restrictionInfo: nil,
            schedulingState: nil,
            selfDestructIn: 0,
            selfDestructType: nil,
            senderBoostCount: 0,
            senderBusinessBotUserId: 0,
            senderId: .messageSenderUser(MessageSenderUser(userId: senderUserId)),
            senderTag: "",
            sendingState: sendingState,
            suggestedPostInfo: nil,
            summaryLanguageCode: "",
            topicId: nil,
            unreadReactions: [],
            viaBotUserId: 0
        )
    }
}
