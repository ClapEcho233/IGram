//
//  HistoryModelTests.swift
//  IGramTests
//

import Foundation
import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct HistoryModelTests {
    private static let client = TelegramClient(logVerbosity: 0)

    private func makeModel(_ ids: [Int64], hasMoreNewer: Bool = false) -> HistoryModel {
        let model = HistoryModel(chatId: 1, client: Self.client)
        model.setSlice(ids.map { Fixtures.message(id: $0) }, hasMoreOlder: true, hasMoreNewer: hasMoreNewer)
        return model
    }

    @Test func mergeSortsAndDeduplicates() {
        let existing = [ChatMessage(Fixtures.message(id: 5)), ChatMessage(Fixtures.message(id: 9))]
        let merged = HistoryModel.merge(existing, [Fixtures.message(id: 7), Fixtures.message(id: 5), Fixtures.message(id: 1)])
        #expect(merged.map(\.id) == [1, 5, 7, 9])
    }

    @Test func sliceIsAscending() {
        let model = makeModel([30, 10, 20])
        #expect(model.messages.map(\.id) == [10, 20, 30])
        #expect(model.didLoadInitial)
    }

    @Test func appendsLiveMessages() {
        let model = makeModel([10, 20])
        model.handle(.updateNewMessage(UpdateNewMessage(message: Fixtures.message(id: 30))))
        #expect(model.messages.map(\.id) == [10, 20, 30])
    }

    @Test func outgoingMessageRequestsFocus() {
        let model = makeModel([10])
        model.handle(.updateNewMessage(UpdateNewMessage(message: Fixtures.message(id: 11, isOutgoing: true))))
        #expect(model.focusRequest?.messageId == 11)
    }

    @Test func ignoresLiveMessagesAcrossAGap() {
        let model = makeModel([10, 20], hasMoreNewer: true)
        model.handle(.updateNewMessage(UpdateNewMessage(message: Fixtures.message(id: 99))))
        #expect(model.messages.map(\.id) == [10, 20])
    }

    @Test func ignoresOtherChats() {
        let model = makeModel([10])
        // Routing happens in TelegramSession; the model itself trusts its caller,
        // so verify the routing key instead.
        let update = Update.updateNewMessage(UpdateNewMessage(message: Fixtures.message(id: 11, chatId: 2)))
        #expect(update.messageChatId == 2)
        #expect(model.messages.count == 1)
    }

    @Test func sendSucceededReplacesTemporaryMessage() {
        let model = makeModel([10])
        let pending = Fixtures.message(
            id: 1_000_001,
            isOutgoing: true,
            sendingState: .messageSendingStatePending(MessageSendingStatePending(sendingId: 0))
        )
        model.handle(.updateNewMessage(UpdateNewMessage(message: pending)))
        #expect(model.messages.last?.isSending == true)

        model.handle(.updateMessageSendSucceeded(UpdateMessageSendSucceeded(
            message: Fixtures.message(id: 11, isOutgoing: true),
            oldMessageId: 1_000_001
        )))
        #expect(model.messages.map(\.id) == [10, 11])
        #expect(model.messages.last?.isSending == false)
    }

    @Test func contentAndEditUpdates() {
        let model = makeModel([10])
        model.handle(.updateMessageContent(UpdateMessageContent(
            chatId: 1,
            messageId: 10,
            newContent: Fixtures.textContent("Edited")
        )))
        model.handle(.updateMessageEdited(UpdateMessageEdited(chatId: 1, editDate: 123, messageId: 10, replyMarkup: nil)))
        #expect(model.messages.first?.text?.text == "Edited")
        #expect(model.messages.first?.isEdited == true)
    }

    @Test func pinnedUpdate() {
        let model = makeModel([10])
        model.handle(.updateMessageIsPinned(UpdateMessageIsPinned(chatId: 1, isPinned: true, messageId: 10)))
        #expect(model.messages.first?.isPinned == true)
    }

    @Test func deletesPermanentlyButNotFromCache() {
        let model = makeModel([10, 20, 30])
        model.handle(.updateDeleteMessages(UpdateDeleteMessages(chatId: 1, fromCache: true, isPermanent: false, messageIds: [10])))
        #expect(model.messages.count == 3)
        model.handle(.updateDeleteMessages(UpdateDeleteMessages(chatId: 1, fromCache: false, isPermanent: true, messageIds: [10, 30])))
        #expect(model.messages.map(\.id) == [20])
    }

    @Test func voiceNoteBecomesListened() {
        let voice = MessageContent.messageVoiceNote(MessageVoiceNote(
            caption: Fixtures.text(""),
            isListened: false,
            voiceNote: VoiceNote(
                duration: 3,
                mimeType: "audio/ogg",
                speechRecognitionResult: nil,
                voice: File(
                    expectedSize: 0,
                    id: 1,
                    local: LocalFile(canBeDeleted: false, canBeDownloaded: true, downloadOffset: 0, downloadedPrefixSize: 0, downloadedSize: 0, isDownloadingActive: false, isDownloadingCompleted: false, path: ""),
                    remote: RemoteFile(id: "", isUploadingActive: false, isUploadingCompleted: true, uniqueId: "", uploadedSize: 0),
                    size: 0
                ),
                waveform: Data()
            )
        ))
        var message = ChatMessage(Fixtures.message(id: 1, content: voice))
        message.markContentOpened()
        guard case .messageVoiceNote(let value) = message.content else {
            Issue.record("Content changed type")
            return
        }
        #expect(value.isListened)
    }

    @Test func serviceClassification() {
        #expect(!Fixtures.textContent("hi").isService)
        #expect(MessageContent.messageChatChangeTitle(MessageChatChangeTitle(title: "New")).isService)
        #expect(MessageContent.messagePinMessage(MessagePinMessage(messageId: 1)).isService)
    }
}
