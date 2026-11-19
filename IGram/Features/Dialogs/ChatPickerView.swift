//
//  ChatPickerView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// A searchable list of chats to pick a destination from, like tdesktop's
/// `ChooseRecipientBoxController`.
struct ChatPickerView: View {
    /// Folders can hold channels the user can't post in; forwarding can't.
    var includesReadOnlyChats = false
    let onPick: (ChatItem) -> Void

    @Environment(TelegramSession.self) private var session
    @State private var query = ""
    @State private var searchResults: [Int64]?

    var body: some View {
        let ids = searchResults ?? session.chats.list(.chatListMain).chatIds
        let chats = ids.compactMap(session.chats.chat).filter { includesReadOnlyChats || session.composerAvailability(for: $0) == .canSend }
        VStack(spacing: 0) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            List(chats) { chat in
                Button {
                    onPick(chat)
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 32)
                        Text(session.title(of: chat)).lineLimit(1)
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                searchResults = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            searchResults = (try? await session.api.searchChats(limit: 50, query: trimmed, typeFilter: nil))?.chatIds
        }
    }
}

/// Picks a chat and forwards messages there.
struct ForwardSheet: View {
    let messages: [ChatMessage]
    let fromChatId: Int64

    @Environment(TelegramSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(messages.count == 1 ? String(localized: "Forward Message") : String(localized: "Forward \(messages.count) Messages"))
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top], 16)
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red).padding(.top, 8)
            }
            ChatPickerView { chat in forward(to: chat) }
        }
        .frame(width: 380, height: 480)
    }

    private func forward(to chat: ChatItem) {
        let ids = messages.map(\.id)
        Task {
            do {
                _ = try await session.api.forwardMessages(
                    chatId: chat.id,
                    fromChatId: fromChatId,
                    messageIds: ids,
                    options: nil,
                    removeCaption: false,
                    sendCopy: false,
                    topicId: nil
                )
                dismiss()
            } catch {
                errorMessage = error.telegramMessage
                Log.ui.error("Forward failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }
}
