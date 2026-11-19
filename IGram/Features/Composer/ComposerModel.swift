//
//  ComposerModel.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// State of the message field of one chat: text, reply or edit target, and
/// sending. tdesktop keeps the same in `HistoryWidget` and `Data::Draft`.
@Observable
final class ComposerModel {
    enum Mode: Equatable {
        case compose
        case reply(ChatMessage)
        case edit(ChatMessage)

        var message: ChatMessage? {
            switch self {
            case .compose: nil
            case .reply(let message), .edit(let message): message
            }
        }
    }

    /// How a message is sent, from the send button's menu.
    nonisolated struct SendOptions: Equatable, Sendable {
        var isSilent = false
        var scheduleDate: Date?
        var whenOnline = false

        static let standard = SendOptions()

        var messageSendOptions: MessageSendOptions? {
            guard self != .standard else { return nil }
            let scheduling: MessageSchedulingState? = if whenOnline {
                .messageSchedulingStateSendWhenOnline
            } else if let scheduleDate {
                .messageSchedulingStateSendAtDate(MessageSchedulingStateSendAtDate(
                    repeatPeriod: 0,
                    sendDate: Int(scheduleDate.timeIntervalSince1970)
                ))
            } else {
                nil
            }
            return MessageSendOptions(
                allowPaidBroadcast: false,
                disableNotification: isSilent,
                effectId: 0,
                fromBackground: false,
                onlyPreview: false,
                paidMessageStarCount: 0,
                protectContent: false,
                schedulingState: scheduling,
                sendingId: 0,
                suggestedPostInfo: nil,
                updateOrderOfInstalledStickerSets: false
            )
        }
    }

    let chatId: Int64
    var text = "" {
        didSet {
            guard text != oldValue else { return }
            textDidChange()
        }
    }
    private(set) var mode: Mode = .compose
    private(set) var isSending = false
    var errorMessage: String?
    /// Incremented to ask the text view to take keyboard focus.
    private(set) var focusRequest = 0

    @ObservationIgnored private let session: TelegramSession
    @ObservationIgnored private var lastTypingSent: Date = .distantPast
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var isRestoringDraft = false
    @ObservationIgnored private var textBeforeEdit = ""

    init(chat: ChatItem, session: TelegramSession) {
        chatId = chat.id
        self.session = session
        if case .draftMessageContentText(let content) = chat.draftMessage?.content {
            isRestoringDraft = true
            text = content.text.text
            isRestoringDraft = false
        }
    }

    var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: - Modes

    func reply(to message: ChatMessage) {
        if case .edit = mode { text = textBeforeEdit }
        mode = .reply(message)
        focus()
        scheduleDraftSave()
    }

    func edit(_ message: ChatMessage) {
        if case .edit = mode {} else { textBeforeEdit = text }
        mode = .edit(message)
        let original = message.text ?? FormattedText(entities: [], text: "")
        isRestoringDraft = true
        text = original.text
        isRestoringDraft = false
        focus()
        Task {
            // Show formatting as Markdown so it survives the edit.
            if let markdown = try? await session.api.getMarkdownText(text: original), case .edit(let current) = mode, current.id == message.id {
                isRestoringDraft = true
                text = markdown.text
                isRestoringDraft = false
            }
        }
    }

    /// Escape: leave edit or reply mode.
    @discardableResult
    func cancelMode() -> Bool {
        switch mode {
        case .compose:
            return false
        case .reply:
            mode = .compose
            scheduleDraftSave()
        case .edit:
            mode = .compose
            isRestoringDraft = true
            text = textBeforeEdit
            isRestoringDraft = false
        }
        return true
    }

    func focus() { focusRequest += 1 }

    // MARK: - Sending

    func submit(options: SendOptions = .standard) {
        guard canSubmit else { return }
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = mode
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let formatted = try await formattedText(from: raw)
                switch mode {
                case .edit(let message):
                    try await saveEdit(of: message, text: formatted)
                    self.mode = .compose
                    isRestoringDraft = true
                    text = textBeforeEdit
                    isRestoringDraft = false
                case .compose, .reply:
                    try await send(
                        .inputMessageText(InputMessageText(clearDraft: true, linkPreviewOptions: nil, text: formatted)),
                        replyTo: mode.message,
                        options: options
                    )
                    self.mode = .compose
                    isRestoringDraft = true
                    text = ""
                    isRestoringDraft = false
                }
                errorMessage = nil
            } catch {
                errorMessage = error.telegramMessage
                Log.ui.error("Sending failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }

    /// Sends arbitrary content, replying to the current reply target if any.
    func send(_ content: InputMessageContent, replyTo: ChatMessage? = nil, options: SendOptions = .standard) async throws {
        let reply = (replyTo ?? replyTarget).map(Self.replyReference)
        _ = try await session.api.sendMessage(
            chatId: chatId,
            inputMessageContent: content,
            options: options.messageSendOptions,
            replyMarkup: nil,
            replyTo: reply,
            topicId: nil
        )
        if case .reply = mode { mode = .compose }
    }

    /// Sends several items as one album.
    func sendAlbum(_ contents: [InputMessageContent], options: SendOptions = .standard) async throws {
        let reply = replyTarget.map(Self.replyReference)
        _ = try await session.api.sendMessageAlbum(
            chatId: chatId,
            inputMessageContents: contents,
            options: options.messageSendOptions,
            replyTo: reply,
            topicId: nil
        )
        if case .reply = mode { mode = .compose }
    }

    /// The message being replied to, if the composer is in reply mode.
    var replyTarget: ChatMessage? {
        if case .reply(let message) = mode { return message }
        return nil
    }

    static func replyReference(_ message: ChatMessage) -> InputMessageReplyTo {
        .inputMessageReplyToMessage(InputMessageReplyToMessage(checklistTaskId: 0, messageId: message.id, pollOptionId: "", quote: nil))
    }

    private func saveEdit(of message: ChatMessage, text: FormattedText) async throws {
        switch message.content {
        case .messageText:
            _ = try await session.api.editMessageText(
                chatId: chatId,
                inputMessageContent: .inputMessageText(InputMessageText(clearDraft: false, linkPreviewOptions: nil, text: text)),
                messageId: message.id,
                replyMarkup: nil
            )
        default:
            _ = try await session.api.editMessageCaption(
                caption: text,
                chatId: chatId,
                messageId: message.id,
                replyMarkup: nil,
                showCaptionAboveMedia: false
            )
        }
    }

    /// Parses **bold**, __italic__, `code`, ~~strike~~ and ||spoiler|| markup
    /// with TDLib, the same shortcuts tdesktop accepts.
    func formattedText(from raw: String) async throws -> FormattedText {
        let plain = FormattedText(entities: [], text: raw)
        return (try? await session.api.parseMarkdown(text: plain)) ?? plain
    }

    // MARK: - Typing and drafts

    private func textDidChange() {
        guard !isRestoringDraft else { return }
        if case .edit = mode { return }
        if !text.isEmpty, Date.now.timeIntervalSince(lastTypingSent) > 5 {
            lastTypingSent = .now
            let chatId = chatId
            let api = session.api
            Task { _ = try? await api.sendChatAction(action: .chatActionTyping, businessConnectionId: nil, chatId: chatId, topicId: nil) }
        }
        scheduleDraftSave()
    }

    private func scheduleDraftSave() {
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.saveDraft()
        }
    }

    /// Stores the unsent text as the chat's cloud draft.
    func saveDraft() async {
        draftTask?.cancel()
        if case .edit = mode { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyTo = replyTarget.map(Self.replyReference)
        let draft = trimmed.isEmpty ? nil : DraftMessage(
            content: .draftMessageContentText(DraftMessageContentText(linkPreviewOptions: nil, text: FormattedText(entities: [], text: text))),
            date: Int(Date.now.timeIntervalSince1970),
            effectId: 0,
            replyTo: replyTo,
            suggestedPostInfo: nil
        )
        _ = try? await session.api.setChatDraftMessage(chatId: chatId, draftMessage: draft, topicId: nil)
    }
}

/// Whether and how the user can write in a chat.
enum ComposerAvailability: Equatable {
    case canSend
    case join
    case muteToggle(isMuted: Bool)
    case restricted(String)
}

extension TelegramSession {
    func composerAvailability(for chat: ChatItem) -> ComposerAvailability {
        switch chat.type {
        case .chatTypePrivate(let value):
            if peers.user(value.userId).user?.isDeleted == true {
                return .restricted(String(localized: "This account has been deleted."))
            }
            return .canSend
        case .chatTypeSecret(let value):
            if case .secretChatStateClosed = secretChatState(value.secretChatId) {
                return .restricted(String(localized: "This secret chat was closed."))
            }
            return .canSend
        case .chatTypeBasicGroup(let value):
            guard let status = peers.basicGroup(value.basicGroupId).group?.status else { return .canSend }
            return availability(status: status, chat: chat, isChannel: false)
        case .chatTypeSupergroup(let value):
            guard let supergroup = peers.supergroup(value.supergroupId).supergroup else { return .canSend }
            return availability(status: supergroup.status, chat: chat, isChannel: value.isChannel)
        }
    }

    private func secretChatState(_ id: Int) -> SecretChatState? {
        peers.secretChat(id)?.state
    }

    private func availability(status: ChatMemberStatus, chat: ChatItem, isChannel: Bool) -> ComposerAvailability {
        switch status {
        case .chatMemberStatusCreator:
            return .canSend
        case .chatMemberStatusAdministrator(let admin):
            if isChannel, !admin.rights.canPostMessages { return .muteToggle(isMuted: chats.isMuted(chat)) }
            return .canSend
        case .chatMemberStatusLeft:
            return .join
        case .chatMemberStatusBanned:
            return .restricted(String(localized: "You were removed from this chat."))
        case .chatMemberStatusRestricted(let restricted):
            if !restricted.isMember { return .join }
            return restricted.permissions.canSendBasicMessages ? .canSend : .restricted(String(localized: "Sending messages is restricted here."))
        case .chatMemberStatusMember:
            if isChannel { return .muteToggle(isMuted: chats.isMuted(chat)) }
            return chat.permissions.canSendBasicMessages ? .canSend : .restricted(String(localized: "Only admins can send messages here."))
        }
    }
}
