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
    @State private var inChatSearch = InChatSearchModel()
    @State private var pinned: PinnedMessagesModel?

    var body: some View {
        VStack(spacing: 0) {
            if inChatSearch.isActive {
                InChatSearchBar(model: inChatSearch, history: history)
            } else if let pinned {
                PinnedMessageBar(model: pinned, history: history)
            }
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if inChatSearch.isActive { inChatSearch.close() } else { inChatSearch.isActive = true }
                } label: {
                    Label("Search in Chat", systemImage: "magnifyingglass")
                }
                .help("Search in this chat")
                .keyboardShortcut("f", modifiers: [.command])
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    main.isInfoPresented.toggle()
                } label: {
                    Label("Info", systemImage: "sidebar.right")
                }
                .help("Show chat info")
                .keyboardShortcut("i", modifiers: [.command])
            }
        }
        .inspector(isPresented: Bindable(main).isInfoPresented) {
            ChatInfoView(chat: chat)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
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
            pinned?.detach()
            history.close()
            if let composer { Task { await composer.saveDraft() } }
        }
        .task(id: chat.id) {
            // Load the profile used by the header subtitle and the info panel.
            await session.loadFullInfo(for: chat)
        }
        .task(id: chat.id) {
            let model = pinned ?? PinnedMessagesModel(chatId: chat.id)
            pinned = model
            await model.attach(to: session)
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
