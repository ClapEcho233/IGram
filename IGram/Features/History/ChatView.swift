//
//  ChatView.swift
//  IGram
//

import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import TDLibKit

/// An open chat: header, history and composer, accepting dropped files.
/// Corresponds to tdesktop's `HistoryWidget`.
struct ChatView: View {
    let chat: ChatItem
    let history: HistoryModel

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @State private var unreadAnchor: Int64?
    @State private var composer: ComposerModel?
    @State private var attachments: AttachmentBatch?
    @State private var isPickingFiles = false
    @State private var isDropTargeted = false
    @State private var messageActions = MessageActionsModel()

    var body: some View {
        VStack(spacing: 0) {
            HistoryView(chat: chat, history: history, unreadAnchor: unreadAnchor)
            if let composer {
                ComposerView(
                    chat: chat,
                    model: composer,
                    history: history,
                    onAttachFiles: { urls in
                        attach(urls)
                        return true
                    },
                    onAttachButton: { isPickingFiles = true }
                )
            }
        }
        .environment(composer)
        .environment(messageActions)
        .messageActionPresentations(messageActions, chat: chat, session: session)
        .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { attach(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard canSend else { return false }
            attach(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted, canSend {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(.tint.opacity(0.08), in: .rect(cornerRadius: 12))
                    .overlay {
                        Label("Drop files here to send them", systemImage: "square.and.arrow.down")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $attachments) { batch in
            if let composer {
                SendFilesSheet(batch: batch, composer: composer)
            }
        }
        .navigationTitle(session.title(of: chat))
        .navigationSubtitle(session.subtitle(for: chat))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 28)
            }
        }
        .task(id: chat.id) {
            if composer == nil { composer = ComposerModel(chat: chat, session: session) }
            unreadAnchor = chat.unreadCount > 0 ? chat.lastReadInboxMessageId : nil
            await history.open(unreadCount: chat.unreadCount, lastReadInboxMessageId: chat.lastReadInboxMessageId)
            await jumpToPendingMessage()
        }
        .onChange(of: main.pendingMessageId) {
            Task { await jumpToPendingMessage() }
        }
        .onDisappear {
            history.close()
            if let composer { Task { await composer.saveDraft() } }
        }
        .task(id: chat.userId) {
            // Keep presence and profile details fresh while the chat is open.
            if let userId = chat.userId {
                _ = try? await session.api.getUserFullInfo(userId: userId)
            }
        }
    }

    private var canSend: Bool {
        session.composerAvailability(for: chat) == .canSend
    }

    private func attach(_ urls: [URL]) {
        guard !urls.isEmpty, canSend else { return }
        Task {
            let items = await AttachmentPreparer.prepare(urls)
            if !items.isEmpty { attachments = AttachmentBatch(items: items) }
        }
    }

    private func jumpToPendingMessage() async {
        guard let messageId = main.pendingMessageId, main.selectedChatId == chat.id else { return }
        main.pendingMessageId = nil
        await history.jump(to: messageId)
    }
}
