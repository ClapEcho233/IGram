//
//  MessageActions.swift
//  IGram
//

import AppKit
import Observation
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Pending message actions that need a dialog or sheet, owned by the chat view.
@Observable
final class MessageActionsModel {
    struct Deletion: Identifiable {
        let messages: [ChatMessage]
        let canDeleteForEveryone: Bool
        let canDeleteForSelf: Bool
        var id: Int64 { messages.first?.id ?? 0 }
    }

    struct Forwarding: Identifiable {
        let messages: [ChatMessage]
        var id: Int64 { messages.first?.id ?? 0 }
    }

    var deletion: Deletion?
    var forwarding: Forwarding?
    /// Messages chosen in selection mode, like tdesktop's `HistoryInner::_selected`.
    private(set) var selectedIds: Set<Int64> = []

    var isSelecting: Bool { !selectedIds.isEmpty }

    func toggleSelection(of ids: [Int64]) {
        if ids.allSatisfy(selectedIds.contains) {
            selectedIds.subtract(ids)
        } else {
            selectedIds.formUnion(ids)
        }
    }

    func clearSelection() { selectedIds.removeAll() }

    /// Selected messages in chronological order.
    func selectedMessages(in history: HistoryModel) -> [ChatMessage] {
        selectedIds.sorted().compactMap(history.message)
    }
}

/// The context menu of a message, after tdesktop's `HistoryView::FillContextMenu`.
struct MessageContextMenu: View {
    let entry: MessageEntry
    let chat: ChatItem
    let history: HistoryModel

    @Environment(TelegramSession.self) private var session
    @Environment(ComposerModel.self) private var composer: ComposerModel?
    @Environment(MessageActionsModel.self) private var actions: MessageActionsModel?

    private var message: ChatMessage { entry.captionMessage }
    private var properties: MessageProperties? { history.properties[message.id] }

    var body: some View {
        let quick = ReactionActions.quickReactions(for: chat)
        if !quick.isEmpty, !message.isSending, !message.isFailed {
            Menu("React", systemImage: "face.smiling") {
                ForEach(quick, id: \.self) { emoji in
                    let type = ReactionType.reactionTypeEmoji(ReactionTypeEmoji(emoji: emoji))
                    let chosen = message.interactionInfo?.reactions?.reactions.contains { $0.type == type && $0.isChosen } ?? false
                    Button(chosen ? "\(emoji) ✓" : emoji) {
                        ReactionActions.toggle(type, isChosen: chosen, on: message, session: session)
                    }
                }
            }
            Divider()
        }
        if message.isFailed {
            Button("Retry Sending", systemImage: "arrow.clockwise") {
                run { _ = try await session.api.resendMessages(chatId: chat.id, messageIds: entry.messages.map(\.id), paidMessageStarCount: 0, quote: nil) }
            }
        }
        if properties?.canBeReplied ?? true, let composer {
            Button("Reply", systemImage: "arrowshape.turn.up.left") { composer.reply(to: message) }
        }
        if properties?.canBeEdited == true, let composer {
            Button("Edit", systemImage: "pencil") { composer.edit(message) }
        }
        if let text = message.text, !text.text.isEmpty {
            Button("Copy Text", systemImage: "doc.on.doc") { copy(text.text) }
        }
        if ExtraFeatures.shared.showIDs {
            Button("Copy Message ID", systemImage: "number") { copy(String(message.id >> 20)) }
        }
        if properties?.canGetLink == true {
            Button("Copy Message Link", systemImage: "link") {
                run {
                    let link = try await session.api.getMessageLink(
                        chatId: chat.id, checklistTaskId: 0, forAlbum: entry.isAlbum, inMessageThread: false,
                        mediaTimestamp: 0, messageId: message.id, pollOptionId: ""
                    )
                    copy(link.link)
                }
            }
        }
        if properties?.canBePinned == true {
            Button(message.isPinned ? "Unpin" : "Pin", systemImage: message.isPinned ? "pin.slash" : "pin") {
                run {
                    if message.isPinned {
                        try await session.api.unpinChatMessage(chatId: chat.id, messageId: message.id)
                    } else {
                        try await session.api.pinChatMessage(chatId: chat.id, disableNotification: false, messageId: message.id, onlyForSelf: false)
                    }
                }
            }
        }
        if properties?.canBeForwarded == true {
            Button("Forward", systemImage: "arrowshape.turn.up.right") {
                actions?.forwarding = .init(messages: entry.messages)
            }
        }
        if let file = MessageFiles.savableFile(in: message.content), properties?.canBeSaved ?? message.canBeSaved {
            Divider()
            Button("Save As…", systemImage: "square.and.arrow.down") { save(file) }
            if session.files.item(for: file).isDownloaded {
                Button("Show in Finder", systemImage: "folder") {
                    if let url = session.files.item(for: file).localURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
        Button("Select", systemImage: "checkmark.circle") {
            actions?.toggleSelection(of: entry.messages.map(\.id))
        }
        if let properties, properties.canBeDeletedOnlyForSelf || properties.canBeDeletedForAllUsers {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                actions?.deletion = .init(
                    messages: entry.messages,
                    canDeleteForEveryone: properties.canBeDeletedForAllUsers,
                    canDeleteForSelf: properties.canBeDeletedOnlyForSelf
                )
            }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func save(_ file: File) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = MessageFiles.suggestedName(for: message.content)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        run {
            let source = try await session.files.downloadedURL(for: file)
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                Log.ui.error("Message action failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }
}

/// Files that can be saved from a message.
enum MessageFiles {
    static func savableFile(in content: MessageContent) -> File? {
        switch content {
        case .messagePhoto(let value): MediaSizing.largestSize(of: value.photo)?.photo
        case .messageVideo(let value): value.video.video
        case .messageAnimation(let value): value.animation.animation
        case .messageDocument(let value): value.document.document
        case .messageAudio(let value): value.audio.audio
        case .messageVoiceNote(let value): value.voiceNote.voice
        case .messageVideoNote(let value): value.videoNote.video
        default: nil
        }
    }

    static func suggestedName(for content: MessageContent) -> String {
        switch content {
        case .messageDocument(let value) where !value.document.fileName.isEmpty: value.document.fileName
        case .messageAudio(let value) where !value.audio.fileName.isEmpty: value.audio.fileName
        case .messageVideo(let value) where !value.video.fileName.isEmpty: value.video.fileName
        case .messagePhoto: "Photo.jpg"
        case .messageVideo, .messageVideoNote, .messageAnimation: "Video.mp4"
        case .messageVoiceNote: "Voice.ogg"
        default: "File"
        }
    }
}

extension View {
    /// Delete confirmation and forward sheet for the chat's message actions.
    func messageActionPresentations(_ actions: MessageActionsModel, chat: ChatItem, session: TelegramSession) -> some View {
        @Bindable var actions = actions
        return self
            .confirmationDialog(
                actions.deletion.map { $0.messages.count > 1 ? String(localized: "Delete \($0.messages.count) messages?") : String(localized: "Delete message?") } ?? "",
                item: $actions.deletion
            ) { deletion in
                let ids = deletion.messages.map(\.id)
                if deletion.canDeleteForEveryone {
                    Button(chat.userId != nil ? String(localized: "Delete for Me and \(session.title(of: chat))") : String(localized: "Delete for Everyone"), role: .destructive) {
                        session.archive.expectDeletion(chatId: chat.id, messageIds: ids)
                        Task { try? await session.api.deleteMessages(chatId: chat.id, messageIds: ids, revoke: true) }
                    }
                }
                if deletion.canDeleteForSelf {
                    Button("Delete for Me", role: .destructive) {
                        session.archive.expectDeletion(chatId: chat.id, messageIds: ids)
                        Task { try? await session.api.deleteMessages(chatId: chat.id, messageIds: ids, revoke: false) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This action can't be undone.")
            }
            .sheet(item: $actions.forwarding) { forwarding in
                ForwardSheet(messages: forwarding.messages, fromChatId: chat.id)
            }
    }
}
