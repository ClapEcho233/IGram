//
//  MessageFormatter.swift
//  IGram
//

import Foundation
@preconcurrency import TDLibKit

/// Produces the one-line previews and service texts shown in the chat list,
/// reply headers, notifications and service bubbles.
///
/// The wording follows tdesktop's `lng_action_*` and media preview strings.
struct MessageFormatter {
    /// Resolves a user id to a display name.
    var userName: (Int64) -> String
    /// Resolves a chat id to its title.
    var chatTitle: (Int64) -> String
    /// Returns the preview of another message, used for "pinned …" notices.
    var messagePreview: (Int64) -> String? = { _ in nil }

    func senderName(_ sender: MessageSender) -> String {
        switch sender {
        case .messageSenderUser(let value): userName(value.userId)
        case .messageSenderChat(let value): chatTitle(value.chatId)
        }
    }

    // MARK: - Previews

    /// A single-line summary of the content, e.g. "📷 Photo, caption".
    func preview(_ content: MessageContent) -> String {
        func withCaption(_ label: String, _ caption: FormattedText) -> String {
            caption.text.isEmpty ? label : "\(label), \(caption.text.singleLine)"
        }

        switch content {
        case .messageText(let value):
            return value.text.text.singleLine
        case .messagePhoto(let value):
            return withCaption(String(localized: "Photo"), value.caption)
        case .messageVideo(let value):
            return withCaption(String(localized: "Video"), value.caption)
        case .messageAnimation(let value):
            return withCaption(String(localized: "GIF"), value.caption)
        case .messageDocument(let value):
            let name = value.document.fileName.isEmpty ? String(localized: "File") : value.document.fileName
            return withCaption(name, value.caption)
        case .messageAudio(let value):
            let audio = value.audio
            let title = [audio.performer, audio.title].filter { !$0.isEmpty }.joined(separator: " – ")
            return withCaption(title.isEmpty ? String(localized: "Audio file") : title, value.caption)
        case .messageVoiceNote(let value):
            return withCaption(String(localized: "Voice message"), value.caption)
        case .messageVideoNote:
            return String(localized: "Video message")
        case .messageSticker(let value):
            let emoji = value.sticker.emoji
            return emoji.isEmpty ? String(localized: "Sticker") : "\(emoji) \(String(localized: "Sticker"))"
        case .messageAnimatedEmoji(let value):
            return value.emoji
        case .messageDice(let value):
            return value.emoji
        case .messageLocation, .messageLiveLocation:
            return String(localized: "Location")
        case .messageVenue(let value):
            return value.venue.title.isEmpty ? String(localized: "Location") : value.venue.title
        case .messageContact(let value):
            let name = [value.contact.firstName, value.contact.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            return name.isEmpty ? String(localized: "Contact") : "\(String(localized: "Contact")): \(name)"
        case .messagePoll(let value):
            return "📊 \(value.poll.question.text.singleLine)"
        case .messageGame:
            return String(localized: "Game")
        case .messageInvoice:
            return String(localized: "Invoice")
        case .messageStory:
            return String(localized: "Story")
        case .messageCall(let value):
            return callDescription(value)
        case .messageExpiredPhoto:
            return String(localized: "Photo has expired")
        case .messageExpiredVideo:
            return String(localized: "Video has expired")
        case .messageExpiredVoiceNote:
            return String(localized: "Voice message has expired")
        case .messageExpiredVideoNote:
            return String(localized: "Video message has expired")
        case .messagePaidMedia:
            return String(localized: "Paid media")
        case .messageChecklist:
            return String(localized: "Checklist")
        case .messageUnsupported:
            return String(localized: "Unsupported message")
        default:
            return String(localized: "Service message")
        }
    }

    /// Emoji shown before a preview in the chat list, like tdesktop's media icons.
    func previewIcon(_ content: MessageContent) -> String? {
        switch content {
        case .messagePhoto: "photo"
        case .messageVideo, .messageVideoNote: "video"
        case .messageAnimation: "play.rectangle"
        case .messageDocument: "doc"
        case .messageAudio: "music.note"
        case .messageVoiceNote: "mic"
        case .messageLocation, .messageLiveLocation, .messageVenue: "mappin.and.ellipse"
        case .messageContact: "person.crop.circle"
        case .messageCall: "phone"
        default: nil
        }
    }

    func callDescription(_ call: MessageCall, isOutgoing: Bool? = nil) -> String {
        let kind = call.isVideo ? String(localized: "Video call") : String(localized: "Call")
        switch call.discardReason {
        case .callDiscardReasonMissed:
            return call.isVideo ? String(localized: "Missed video call") : String(localized: "Missed call")
        case .callDiscardReasonDeclined:
            return call.isVideo ? String(localized: "Declined video call") : String(localized: "Declined call")
        default:
            guard call.duration > 0 else { return kind }
            return "\(kind) (\(DurationFormatting.short(call.duration)))"
        }
    }

    // MARK: - Service messages

    /// Text for a service message, e.g. "Alice added Bob".
    func serviceText(for message: ChatMessage) -> String {
        let actor = senderName(message.senderId)
        switch message.content {
        case .messageBasicGroupChatCreate(let value):
            return String(localized: "\(actor) created the group “\(value.title)”")
        case .messageSupergroupChatCreate(let value):
            return message.isChannelPost
                ? String(localized: "Channel “\(value.title)” created")
                : String(localized: "\(actor) created the group “\(value.title)”")
        case .messageChatChangeTitle(let value):
            return message.isChannelPost
                ? String(localized: "Channel name changed to “\(value.title)”")
                : String(localized: "\(actor) changed the group name to “\(value.title)”")
        case .messageChatChangePhoto:
            return message.isChannelPost
                ? String(localized: "Channel photo updated")
                : String(localized: "\(actor) updated the group photo")
        case .messageChatDeletePhoto:
            return message.isChannelPost
                ? String(localized: "Channel photo removed")
                : String(localized: "\(actor) removed the group photo")
        case .messageChatAddMembers(let value):
            if value.memberUserIds == [message.senderId.userId] {
                return String(localized: "\(actor) joined the group")
            }
            let names = value.memberUserIds.map(userName).formatted(.list(type: .and))
            return String(localized: "\(actor) added \(names)")
        case .messageChatJoinByLink:
            return String(localized: "\(actor) joined the group via invite link")
        case .messageChatJoinByRequest:
            return String(localized: "\(actor) was accepted to the group")
        case .messageChatDeleteMember(let value):
            if value.userId == message.senderId.userId {
                return String(localized: "\(actor) left the group")
            }
            return String(localized: "\(actor) removed \(userName(value.userId))")
        case .messageChatUpgradeTo:
            return String(localized: "Group upgraded to a supergroup")
        case .messageChatUpgradeFrom(let value):
            return String(localized: "Group “\(value.title)” upgraded to a supergroup")
        case .messagePinMessage(let value):
            if let pinned = messagePreview(value.messageId), !pinned.isEmpty {
                return String(localized: "\(actor) pinned “\(pinned.truncated(to: 40))”")
            }
            return String(localized: "\(actor) pinned a message")
        case .messageScreenshotTaken:
            return String(localized: "\(actor) took a screenshot!")
        case .messageContactRegistered:
            return String(localized: "\(actor) joined Telegram")
        case .messageChatSetMessageAutoDeleteTime(let value):
            if value.messageAutoDeleteTime == 0 {
                return String(localized: "\(actor) disabled the auto-delete timer")
            }
            let period = Duration.seconds(value.messageAutoDeleteTime)
                .formatted(.units(allowed: [.weeks, .days, .hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1))
            return String(localized: "\(actor) set messages to auto-delete in \(period)")
        case .messageVideoChatStarted:
            return message.isChannelPost
                ? String(localized: "Live stream started")
                : String(localized: "\(actor) started a video chat")
        case .messageVideoChatEnded(let value):
            return String(localized: "Video chat ended (\(DurationFormatting.short(value.duration)))")
        case .messageVideoChatScheduled:
            return String(localized: "\(actor) scheduled a video chat")
        case .messageInviteVideoChatParticipants(let value):
            let names = value.userIds.map(userName).formatted(.list(type: .and))
            return String(localized: "\(actor) invited \(names) to the video chat")
        case .messageGameScore(let value):
            return String(localized: "\(actor) scored \(value.score)")
        case .messageCustomServiceAction(let value):
            return value.text
        case .messageForumTopicCreated(let value):
            return String(localized: "Topic “\(value.name)” created")
        case .messageForumTopicEdited:
            return String(localized: "\(actor) edited the topic")
        case .messageChatBoost(let value):
            return String(localized: "\(actor) boosted the group \(value.boostCount) times")
        case .messageChatSetTheme:
            return String(localized: "\(actor) changed the chat theme")
        case .messageChatSetBackground:
            return String(localized: "\(actor) set a new wallpaper")
        case .messageChatOwnerChanged(let value):
            return String(localized: "\(userName(value.newOwnerUserId)) is now the owner")
        case .messageChatOwnerLeft(let value):
            return String(localized: "\(actor) left; \(userName(value.newOwnerUserId)) is now the owner")
        case .messageGiftedPremium:
            return String(localized: "\(actor) sent a Telegram Premium gift")
        case .messageGift, .messageUpgradedGift:
            return String(localized: "\(actor) sent a gift")
        case .messagePaymentSuccessful:
            return String(localized: "Payment successful")
        case .messageBotWriteAccessAllowed:
            return String(localized: "You allowed this bot to message you")
        case .messageProximityAlertTriggered(let value):
            return String(localized: "\(senderName(value.travelerId)) is within \(value.distance) m of \(senderName(value.watcherId))")
        case .messageChatHasProtectedContentToggled(let value):
            return value.newHasProtectedContent
                ? String(localized: "\(actor) restricted saving content")
                : String(localized: "\(actor) allowed saving content")
        default:
            return preview(message.content)
        }
    }
}

extension String {
    /// Collapses line breaks for single-line previews.
    var singleLine: String {
        split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    func truncated(to length: Int) -> String {
        count > length ? String(prefix(length)) + "…" : self
    }
}
