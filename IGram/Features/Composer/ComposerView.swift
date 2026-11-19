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
    @State private var fieldHeight: CGFloat = 30
    @State private var keyboardMessage: Message?
    @State private var isKeyboardVisible = true
    @State private var isScheduling = false
    @State private var voice = VoiceRecordingModel()
    @State private var scheduleDate = Date.now

    var body: some View {
        VStack(spacing: 0) {
            Divider()
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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
        }
        .background(.bar)
        .onDisappear { voice.cancel() }
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

    private var editor: some View {
        VStack(spacing: 0) {
            if let message = model.mode.message {
                modeBar(for: message)
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }
            if isKeyboardVisible, let message = keyboardMessage, case .replyMarkupShowKeyboard(let markup) = message.replyMarkup {
                ReplyKeyboardView(chat: chat, markup: markup, markupMessage: message, composer: model) {
                    isKeyboardVisible = false
                }
                Divider()
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onAttachButton) {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Attach files")

                if voice.isRecording {
                    VoiceRecordingBar(model: voice) { voice.cancel() }
                } else {
                    ComposerTextView(
                        text: $model.text,
                        placeholder: placeholder,
                        focusRequest: model.focusRequest,
                        onSubmit: { model.submit() },
                        onEditLast: editLastMessage,
                        onCancel: { model.cancelMode() },
                        onPasteFiles: onAttachFiles,
                        height: $fieldHeight
                    )
                    .frame(height: fieldHeight)
                }

                if case .replyMarkupShowKeyboard = keyboardMessage?.replyMarkup {
                    Button {
                        isKeyboardVisible.toggle()
                    } label: {
                        Image(systemName: isKeyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                            .font(.title3)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(isKeyboardVisible ? "Hide bot keyboard" : "Show bot keyboard")
                }

                if showsMicrophone {
                    Button {
                        Task {
                            if let error = await voice.start(chatId: chat.id, api: session.api) {
                                model.errorMessage = error
                            }
                        }
                    } label: {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .help("Record a voice message")
                } else if voice.isRecording {
                    Button { sendRecording() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .keyboardShortcut(.return, modifiers: [])
                    .help("Send voice message")
                } else {
                    Button { model.submit() } label: {
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.canSubmit ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
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
                    .disabled(!model.canSubmit)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
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
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}
