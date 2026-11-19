//
//  ChatContextMenu.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Pending destructive chat action awaiting confirmation.
struct ChatRemoval: Identifiable {
    enum Kind { case delete, leave }
    let chat: ChatItem
    let kind: Kind
    var id: Int64 { chat.id }
}

/// Context menu of a chat list row, after tdesktop's `FillDialogsEntryMenu`.
struct ChatContextMenu: View {
    let chat: ChatItem
    let chatList: ChatList
    let onRemove: (ChatRemoval) -> Void

    @Environment(TelegramSession.self) private var session

    var body: some View {
        let pinned = chat.isPinned(in: chatList)
        Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") {
            run { try await session.setPinned(chat, in: chatList, pinned: !pinned) }
        }

        if chat.hasUnread {
            Button("Mark as Read", systemImage: "envelope.open") {
                run { try await session.markAsRead(chat) }
            }
        } else {
            Button("Mark as Unread", systemImage: "envelope.badge") {
                run { try await session.markAsUnread(chat) }
            }
        }

        if !session.isSavedMessages(chat) {
            let muted = session.chats.isMuted(chat)
            Button(muted ? "Unmute" : "Mute", systemImage: muted ? "speaker.wave.2" : "speaker.slash") {
                run { try await session.setMuted(chat, muted: !muted) }
            }

            let archived = session.isArchived(chat)
            Button(archived ? "Unarchive" : "Archive", systemImage: archived ? "tray.and.arrow.up" : "archivebox") {
                run { try await session.setArchived(chat, archived: !archived) }
            }
        }

        Divider()

        if session.canLeave(chat) {
            Button(chat.isChannel ? "Leave Channel" : "Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                onRemove(ChatRemoval(chat: chat, kind: .leave))
            }
        } else {
            Button("Delete Chat", systemImage: "trash", role: .destructive) {
                onRemove(ChatRemoval(chat: chat, kind: .delete))
            }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                Log.ui.error("Chat action failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }
}

extension View {
    /// Confirms deleting or leaving a chat.
    func chatRemovalConfirmation(_ removal: Binding<ChatRemoval?>, session: TelegramSession) -> some View {
        confirmationDialog("Are you sure?", item: removal) { removal in
            switch removal.kind {
            case .leave:
                Button(removal.chat.isChannel ? "Leave Channel" : "Leave Group", role: .destructive) {
                    Task { try? await session.leave(removal.chat) }
                }
            case .delete:
                Button("Delete for Me", role: .destructive) {
                    Task { try? await session.deleteChat(removal.chat) }
                }
                if removal.chat.canBeDeletedForAllUsers {
                    Button("Delete for Everyone", role: .destructive) {
                        Task { try? await session.deleteChat(removal.chat, forEveryone: true) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { removal in
            switch removal.kind {
            case .leave:
                Text("You will leave “\(session.title(of: removal.chat))”.")
            case .delete:
                Text("The chat with “\(session.title(of: removal.chat))” will be deleted.")
            }
        }
    }
}
