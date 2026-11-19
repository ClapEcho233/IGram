//
//  BotKeyboards.swift
//  IGram
//

import AppKit
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Buttons attached under a bot message, after tdesktop's `HistoryMessageReplyMarkup`.
struct InlineKeyboardView: View {
    let message: ChatMessage
    let rows: [[InlineKeyboardButton]]

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(ComposerModel.self) private var composer: ComposerModel?
    @Environment(\.openURL) private var openURL
    @State private var pendingButton: String?

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 3) {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, button in
                        let key = "\(rowIndex)-\(column)"
                        Button {
                            press(button, key: key)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if pendingButton == key {
                                        ProgressView().controlSize(.small).tint(.white)
                                    } else {
                                        Text(button.text)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 32)
                                if let icon = Self.cornerIcon(for: button.type) {
                                    Image(systemName: icon)
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(4)
                                }
                            }
                            .foregroundStyle(.white)
                            .background(ChatTheme.serviceBackground, in: .rect(cornerRadius: 8))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help(Self.help(for: button.type))
                    }
                }
            }
        }
        .frame(minWidth: 240, maxWidth: 520)
    }

    private func press(_ button: InlineKeyboardButton, key: String) {
        let chatId = message.chatId
        let messageId = message.id
        let api = session.api
        switch button.type {
        case .inlineKeyboardButtonTypeUrl(let value):
            if let url = FormattedText.webURL(from: value.url) { openURL(url) }
        case .inlineKeyboardButtonTypeCallback(let value):
            pendingButton = key
            Task {
                defer { pendingButton = nil }
                do {
                    let answer = try await api.getCallbackQueryAnswer(
                        chatId: chatId,
                        messageId: messageId,
                        payload: .callbackQueryPayloadData(CallbackQueryPayloadData(data: value.data))
                    )
                    show(answer)
                } catch {
                    Log.ui.error("Callback query failed: \(error.telegramMessage, privacy: .public)")
                }
            }
        case .inlineKeyboardButtonTypeLoginUrl(let value):
            Task {
                let login = try? await api.getLoginUrl(allowWriteAccess: true, buttonId: value.id, chatId: chatId, messageId: messageId)
                if let url = URL(string: login?.url ?? value.url) { openURL(url) }
            }
        case .inlineKeyboardButtonTypeWebApp(let value):
            Task {
                guard let botId = message.viaBotUserId != 0 ? message.viaBotUserId : message.senderId.userId else { return }
                let info = try? await api.openWebApp(botUserId: botId, chatId: chatId, parameters: nil, replyTo: nil, topicId: nil, url: value.url)
                if let url = URL(string: info?.url.url ?? value.url) { openURL(url) }
            }
        case .inlineKeyboardButtonTypeSwitchInline(let value):
            guard let botId = message.viaBotUserId != 0 ? message.viaBotUserId : message.senderId.userId,
                  let username = session.peers.user(botId).user?.username else { return }
            composer?.text = "@\(username) \(value.query)"
            composer?.focus()
        case .inlineKeyboardButtonTypeCopyText(let value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value.text, forType: .string)
            main.showToast(String(localized: "Copied to clipboard"))
        case .inlineKeyboardButtonTypeUser(let value):
            Task {
                if let chat = try? await api.createPrivateChat(force: false, userId: value.userId) {
                    main.open(chatId: chat.id)
                }
            }
        default:
            main.showToast(String(localized: "This button isn't supported in IGram yet."))
        }
    }

    private func show(_ answer: CallbackQueryAnswer) {
        if !answer.url.isEmpty, let url = URL(string: answer.url) {
            openURL(url)
        }
        guard !answer.text.isEmpty else { return }
        if answer.showAlert {
            let alert = NSAlert()
            alert.messageText = answer.text
            alert.runModal()
        } else {
            main.showToast(answer.text)
        }
    }

    static func cornerIcon(for type: InlineKeyboardButtonType) -> String? {
        switch type {
        case .inlineKeyboardButtonTypeUrl, .inlineKeyboardButtonTypeLoginUrl: "arrow.up.right"
        case .inlineKeyboardButtonTypeSwitchInline: "arrowshape.turn.up.right.fill"
        case .inlineKeyboardButtonTypeWebApp: "app.fill"
        case .inlineKeyboardButtonTypeCopyText: "doc.on.doc"
        default: nil
        }
    }

    static func help(for type: InlineKeyboardButtonType) -> String {
        switch type {
        case .inlineKeyboardButtonTypeUrl(let value): value.url
        case .inlineKeyboardButtonTypeLoginUrl(let value): value.url
        case .inlineKeyboardButtonTypeWebApp(let value): value.url
        default: ""
        }
    }
}

/// A bot's custom keyboard shown above the message field.
struct ReplyKeyboardView: View {
    let chat: ChatItem
    let markup: ReplyMarkupShowKeyboard
    let markupMessage: Message
    let composer: ComposerModel
    let onUsed: () -> Void

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @State private var isConfirmingPhone = false

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(Array(markup.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, button in
                            Button {
                                press(button)
                            } label: {
                                Text(button.text)
                                    .font(.callout)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(.quaternary, in: .rect(cornerRadius: 8))
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(maxHeight: markup.resizeKeyboard ? 180 : 220)
        .fixedSize(horizontal: false, vertical: markup.resizeKeyboard)
        .confirmationDialog("Share your phone number with this bot?", isPresented: $isConfirmingPhone) {
            Button("Share Phone Number") { sharePhoneNumber() }
        }
    }

    private func press(_ button: KeyboardButton) {
        switch button.type {
        case .keyboardButtonTypeText:
            Task {
                let reply = markup.isPersonal || chat.isGroup ? ChatMessage(markupMessage) : nil
                try? await composer.send(
                    .inputMessageText(InputMessageText(clearDraft: false, linkPreviewOptions: nil, text: FormattedText(entities: [], text: button.text))),
                    replyTo: reply
                )
                if markup.oneTime { onUsed() }
            }
        case .keyboardButtonTypeRequestPhoneNumber:
            isConfirmingPhone = true
        default:
            main.showToast(String(localized: "This button isn't supported in IGram yet."))
        }
    }

    private func sharePhoneNumber() {
        guard let me = session.me.user else { return }
        Task {
            try? await composer.send(.inputMessageContact(InputMessageContact(contact: Contact(
                firstName: me.firstName,
                lastName: me.lastName,
                phoneNumber: me.phoneNumber,
                userId: me.id,
                vcard: ""
            ))))
            if markup.oneTime { onUsed() }
        }
    }
}
