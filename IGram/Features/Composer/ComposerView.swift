//
//  ComposerView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// The bottom bar of a chat: reply/edit preview, input field and send button,
/// or a join/mute/restriction bar when the user cannot write.
struct ComposerView: View {
    let chat: ChatItem
    @Bindable var model: ComposerModel
    let history: HistoryModel
    var onAttachFiles: ([URL]) -> Bool = { _ in false }
    var onAttachButton: () -> Void = {}

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @State private var fieldHeight: CGFloat = 30
    @State private var keyboardMessage: Message?
    @State private var isKeyboardVisible = true
    @State private var isScheduling = false
    @State private var voice = VoiceRecordingModel()
    @State private var stickers = StickerLibrary()
    @State private var isShowingPanel = false
    @State private var autocomplete = AutocompleteModel()
    @State private var inlineResults = InlineResultsModel()
    @State private var scheduleDate = Date.now

    var body: some View {
        VStack(spacing: 0) {
            switch session.composerAvailability(for: chat) {
            case .canSend:
                editor
            case .join:
                actionBar(chat.isChannel ? String(localized: "Join Channel") : String(localized: "Join Group")) {
                    _ = try? await session.api.joinChat(chatId: chat.id)
                }
            case .muteToggle(let isMuted):
                actionBar(isMuted ? String(localized: "Unmute") : String(localized: "Mute")) {
                    try? await session.setMuted(chat, muted: !isMuted)
                }
            case .restricted(let reason):
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        }
        .onDisappear { voice.cancel() }
        .onChange(of: main.pendingComposerText) { _, draft in
            guard let draft, draft.chatId == chat.id else { return }
            main.pendingComposerText = nil
            model.text = draft.text
            model.focus()
        }
        .task(id: model.text) {
            await inlineResults.update(text: model.text, chatId: chat.id, isEditing: isEditing, session: session)
        }
        .task(id: model.text) {
            if InlineQuery.parse(model.text) != nil {
                autocomplete.clear()
            } else {
                await autocomplete.update(text: model.text, chat: chat, session: session)
            }
        }
        .sheet(isPresented: $isScheduling) {
            ScheduleSheet(date: $scheduleDate, title: session.isSavedMessages(chat) ? String(localized: "Set a Reminder") : String(localized: "Schedule Message")) {
                model.submit(options: .init(scheduleDate: scheduleDate))
            }
        }
        .task(id: chat.replyMarkupMessageId) {
            // TDLib announces the keyboard message by id at start-up and by value later.
            if let message = chat.replyMarkupMessage {
                keyboardMessage = message
            } else if chat.replyMarkupMessageId != 0 {
                keyboardMessage = try? await session.api.getMessage(chatId: chat.id, messageId: chat.replyMarkupMessageId)
            } else {
                keyboardMessage = nil
            }
            isKeyboardVisible = true
        }
    }

    private var hasAccessoryPanel: Bool {
        model.mode.message != nil || model.errorMessage != nil || inlineResults.isVisible
            || autocomplete.isVisible || showsReplyKeyboard
    }

    private var showsReplyKeyboard: Bool {
        guard isKeyboardVisible, case .replyMarkupShowKeyboard = keyboardMessage?.replyMarkup else { return false }
        return true
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if hasAccessoryPanel {
                // Reply/edit previews, suggestions and bot keyboards float in a
                // card above the field instead of over the transcript.
                VStack(spacing: 0) {
                    if let message = model.mode.message {
                        modeBar(for: message)
                            .padding(.bottom, 8)
                    }
                    if let error = model.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    if inlineResults.isVisible {
                        InlineResultsPanel(chatId: chat.id, model: inlineResults, composer: model)
                    } else if autocomplete.isVisible {
                        AutocompleteList(model: autocomplete) { autocomplete.accept($0, into: model) }
                    }
                    if showsReplyKeyboard, let message = keyboardMessage, case .replyMarkupShowKeyboard(let markup) = message.replyMarkup {
                        ReplyKeyboardView(chat: chat, markup: markup, markupMessage: message, composer: model) {
                            isKeyboardVisible = false
                        }
                    }
                }
                .background(.regularMaterial, in: .rect(cornerRadius: 14, style: .continuous))
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if let menu = botMenuButton {
                    Button {
                        if let botId = chat.userId {
                            let title = session.peers.user(botId).fullName
                            main.openWebApp(
                                title: title.isEmpty ? menu.text : title,
                                launch: .chat(botUserId: botId, chatId: chat.id, url: menu.url, topicId: model.topic)
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "app.fill")
                                .font(.caption)
                            Text(menu.text)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: Self.controlSize)
                        .foregroundStyle(.white)
                        .background(.tint, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .help(menu.text)
                }

                ComposerCircleButton(systemImage: "plus", help: "Attach files", action: onAttachButton)

                HStack(alignment: .bottom, spacing: 4) {
                    if voice.isRecording {
                        VoiceRecordingBar(model: voice) { voice.cancel() }
                            .frame(minHeight: Self.controlSize - 2)
                    } else {
                        ComposerTextView(
                            text: $model.text,
                            placeholder: placeholder,
                            focusRequest: model.focusRequest,
                            insertion: model.insertion,
                            onSubmit: {
                                if !autocomplete.accept(into: model) { model.submit() }
                            },
                            onEditLast: editLastMessage,
                            onArrow: { autocomplete.move($0) },
                            onTab: { autocomplete.accept(into: model) },
                            onCancel: { model.cancelMode() },
                            onPasteFiles: onAttachFiles,
                            height: $fieldHeight
                        )
                        .frame(height: fieldHeight)
                    }
                    trailingFieldButton
                        .frame(height: Self.controlSize - 2)
                }
                .padding(.leading, 12)
                .padding(.trailing, 3)
                .padding(.vertical, 1)
                .frame(minHeight: Self.controlSize)
                .background {
                    let shape = RoundedRectangle(cornerRadius: Self.controlSize / 2, style: .continuous)
                    shape.fill(Color(nsColor: .textBackgroundColor))
                        .overlay { shape.strokeBorder(.separator) }
                }

                if case .replyMarkupShowKeyboard = keyboardMessage?.replyMarkup {
                    ComposerCircleButton(
                        systemImage: isKeyboardVisible ? "keyboard.chevron.compact.down" : "keyboard",
                        help: isKeyboardVisible ? "Hide bot keyboard" : "Show bot keyboard"
                    ) {
                        isKeyboardVisible.toggle()
                    }
                }

                ComposerCircleButton(systemImage: "face.smiling", help: "Emoji, stickers and GIFs") {
                    isShowingPanel.toggle()
                }
                .popover(isPresented: $isShowingPanel, arrowEdge: .top) {
                    TabbedSelector(chatId: chat.id, composer: model, library: stickers) {
                        isShowingPanel = false
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
    }

    /// Height of the input capsule and the round buttons beside it.
    static let controlSize: CGFloat = 34

    /// Inside the end of the field: the microphone while it's empty, otherwise
    /// the blue send arrow, like Messages.
    @ViewBuilder
    private var trailingFieldButton: some View {
        if showsMicrophone {
            Button {
                Task {
                    if let error = await voice.start(chatId: chat.id, api: session.api) {
                        model.errorMessage = error
                    }
                }
            } label: {
                Image(systemName: "mic")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Record a voice message")
        } else if voice.isRecording {
            Button { sendRecording() } label: {
                sendGlyph(systemImage: "arrow.up")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .help("Send voice message")
        } else {
            Button { model.submit() } label: {
                sendGlyph(systemImage: isEditing ? "checkmark" : "arrow.up")
                    .opacity(model.canSubmit ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!model.canSubmit)
            .help(isEditing ? "Save" : "Send — right-click for more options")
            .contextMenu {
                if !isEditing {
                    Button("Send Without Sound", systemImage: "bell.slash") {
                        model.submit(options: .init(isSilent: true))
                    }
                    Button("Schedule Message…", systemImage: "calendar.badge.clock") {
                        scheduleDate = Date.now.addingTimeInterval(3600)
                        isScheduling = true
                    }
                    if chat.userId != nil, !session.isSavedMessages(chat) {
                        Button("Send When Online", systemImage: "person.badge.clock") {
                            model.submit(options: .init(whenOnline: true))
                        }
                    }
                }
            }
        }
    }

    private func sendGlyph(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(.tint, in: .circle)
            .frame(width: 28, height: 28)
            .contentShape(.circle)
    }

    /// Like tdesktop, an empty field offers recording instead of sending.
    private var showsMicrophone: Bool {
        !voice.isRecording && !isEditing && model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendRecording() {
        guard let recorded = voice.finish() else { return }
        Task {
            do {
                try await model.send(.inputMessageVoiceNote(InputMessageVoiceNote(
                    caption: nil,
                    selfDestructType: nil,
                    voiceNote: InputVoiceNote(
                        duration: recorded.duration,
                        voiceNote: .inputFileLocal(InputFileLocal(path: recorded.url.path(percentEncoded: false))),
                        waveform: recorded.waveform
                    )
                )))
            } catch {
                model.errorMessage = error.telegramMessage
            }
        }
    }

    /// A bot's custom Web App menu button, shown beside the composer in private bot chats.
    private var botMenuButton: BotMenuButton? {
        guard let userId = chat.userId,
              let menu = session.peers.user(userId).fullInfo?.botInfo?.menuButton,
              !menu.url.isEmpty else { return nil }
        return menu
    }

    private var isEditing: Bool {
        if case .edit = model.mode { return true }
        return false
    }

    private var placeholder: String {
        if chat.isChannel { return String(localized: "Broadcast") }
        return String(localized: "Write a message…")
    }

    private func modeBar(for message: ChatMessage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isEditing ? "pencil" : "arrowshape.turn.up.left.fill")
                .foregroundStyle(.tint)
                .frame(width: 24)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.tint)
                .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(isEditing ? String(localized: "Edit Message") : String(localized: "Reply to \(session.displayName(message.senderId))"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(session.formatter(history: history).preview(message.content))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.cancelMode()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .contentShape(.rect)
        .onTapGesture {
            Task { await history.jump(to: message.id) }
        }
    }

    /// ↑ in an empty field edits the newest own text message, as in tdesktop.
    private func editLastMessage() -> Bool {
        guard let last = history.messages.last(where: { $0.isOutgoing && !$0.isService && $0.text != nil && !$0.isSending }) else {
            return false
        }
        model.edit(last)
        return true
    }

    private func actionBar(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: 360, minHeight: Self.controlSize)
                .background(Color(nsColor: .textBackgroundColor), in: .capsule)
                .overlay { Capsule().strokeBorder(.separator) }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
}

/// A round button beside the input field, like the + and emoji buttons in Messages.
private struct ComposerCircleButton: View {
    let systemImage: String
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: ComposerView.controlSize, height: ComposerView.controlSize)
                .background(Color(nsColor: .textBackgroundColor), in: .circle)
                .overlay { Circle().strokeBorder(.separator) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
