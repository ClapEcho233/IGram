//
//  ForumTopicsView.swift
//  IGram
//

import Observation
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

extension TelegramSession {
    func isForum(_ chat: ChatItem) -> Bool {
        if case .chatTypeSupergroup(let value) = chat.type {
            return peers.supergroup(value.supergroupId).supergroup?.isForum ?? false
        }
        return false
    }

    /// Forums open on their topic list unless the user chose "View as Messages".
    func showsTopics(_ chat: ChatItem) -> Bool {
        isForum(chat) && chat.viewAsTopics
    }

    func canManageTopics(_ chat: ChatItem) -> Bool {
        adminRights(in: chat)?.canManageTopics ?? false
    }
}

/// The topics of a forum, like tdesktop's `Dialogs::Forum` list.
@Observable
final class ForumTopicsModel {
    let chatId: Int64
    private(set) var topics: [ForumTopic] = []
    private(set) var isLoading = true

    @ObservationIgnored private var observer: UUID?
    @ObservationIgnored private weak var session: TelegramSession?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(chatId: Int64) { self.chatId = chatId }

    func attach(to session: TelegramSession) async {
        self.session = session
        if observer == nil {
            observer = session.addObserver { [weak self] update in
                guard let self else { return }
                switch update {
                case .updateForumTopicInfo(let value) where value.info.chatId == self.chatId:
                    self.scheduleReload()
                case .updateForumTopic(let value) where value.chatId == self.chatId:
                    self.scheduleReload()
                case .updateNewMessage(let value) where value.message.chatId == self.chatId:
                    self.scheduleReload()
                default:
                    break
                }
            }
        }
        await reload()
    }

    func detach() {
        if let observer { session?.removeObserver(observer) }
        observer = nil
        reloadTask?.cancel()
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    func reload() async {
        guard let session else { return }
        defer { isLoading = false }
        do {
            let result = try await session.api.getForumTopics(
                chatId: chatId, limit: 100, offsetDate: 0, offsetForumTopicId: 0, offsetMessageId: 0, query: ""
            )
            topics = result.topics.sorted { $0.order.rawValue > $1.order.rawValue }
        } catch {
            Log.data.error("getForumTopics failed: \(error.telegramMessage, privacy: .public)")
        }
    }
}

struct ForumTopicsView: View {
    let chat: ChatItem

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @State private var model: ForumTopicsModel?
    @State private var isCreating = false
    @State private var newTopicName = ""

    var body: some View {
        List {
            ForEach(model?.topics ?? [], id: \.info.forumTopicId) { topic in
                Button {
                    main.selectedTopic = topic.info
                } label: {
                    ForumTopicRow(topic: topic)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(for: topic) }
            }
        }
        .listStyle(.inset)
        .overlay {
            if model?.isLoading ?? true {
                ProgressView()
            } else if model?.topics.isEmpty == true {
                ContentUnavailableView("No Topics Yet", systemImage: "number")
            }
        }
        .navigationTitle(session.title(of: chat))
        .navigationSubtitle(String(localized: "\(model?.topics.count ?? 0) topics"))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 28)
            }
            if session.canManageTopics(chat) || chat.permissions.canCreateTopics {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Topic", systemImage: "plus.bubble") {
                        newTopicName = ""
                        isCreating = true
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("View as Messages", systemImage: "text.bubble") {
                    Task { try? await session.api.toggleChatViewAsTopics(chatId: chat.id, viewAsTopics: false) }
                }
                .help("Show all topics as one message stream")
            }
        }
        .alert("New Topic", isPresented: $isCreating) {
            TextField("Topic name", text: $newTopicName)
            Button("Create") { create() }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: chat.id) {
            let model = model ?? ForumTopicsModel(chatId: chat.id)
            self.model = model
            await model.attach(to: session)
        }
        .onDisappear { model?.detach() }
    }

    @ViewBuilder
    private func menu(for topic: ForumTopic) -> some View {
        if session.canManageTopics(chat) {
            Button(topic.isPinned ? "Unpin" : "Pin", systemImage: topic.isPinned ? "pin.slash" : "pin") {
                run { try await session.api.toggleForumTopicIsPinned(chatId: chat.id, forumTopicId: topic.info.forumTopicId, isPinned: !topic.isPinned) }
            }
        }
        if session.canManageTopics(chat) || topic.info.isOutgoing {
            Button(topic.info.isClosed ? "Reopen Topic" : "Close Topic", systemImage: topic.info.isClosed ? "lock.open" : "lock") {
                run { try await session.api.toggleForumTopicIsClosed(chatId: chat.id, forumTopicId: topic.info.forumTopicId, isClosed: !topic.info.isClosed) }
            }
        }
        if session.canManageTopics(chat), !topic.info.isGeneral {
            Divider()
            Button("Delete Topic", systemImage: "trash", role: .destructive) {
                run { try await session.api.deleteForumTopic(chatId: chat.id, forumTopicId: topic.info.forumTopicId) }
            }
        }
    }

    private func create() {
        let name = newTopicName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        run {
            let info = try await session.api.createForumTopic(
                chatId: chat.id,
                icon: ForumTopicIcon(color: 0x6FB9F0, customEmojiId: 0),
                isNameImplicit: false,
                name: name
            )
            main.selectedTopic = info
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                main.showToast(error.telegramMessage)
            }
            await model?.reload()
        }
    }
}

private struct ForumTopicRow: View {
    let topic: ForumTopic

    @Environment(TelegramSession.self) private var session

    var body: some View {
        HStack(spacing: 10) {
            ForumTopicIconView(info: topic.info)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(topic.info.name).font(.body.weight(.semibold)).lineLimit(1)
                    if topic.info.isClosed {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let message = topic.lastMessage {
                        Text(DateFormatting().chatListTimestamp(Date(timeIntervalSince1970: TimeInterval(message.date))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text(preview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if topic.unreadMentionCount > 0 {
                        Image(systemName: "at").font(.caption.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(.tint, in: .circle)
                    }
                    if topic.unreadCount > 0 {
                        UnreadBadge(count: topic.unreadCount)
                    } else if topic.isPinned {
                        Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tertiary).rotationEffect(.degrees(45))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    private var preview: String {
        guard let message = topic.lastMessage else { return " " }
        let formatter = session.formatter()
        let chatMessage = ChatMessage(message)
        if chatMessage.isService { return formatter.serviceText(for: chatMessage) }
        return "\(session.shortName(message.senderId)): \(formatter.preview(message.content))"
    }
}

/// tdesktop draws topic icons as a colored bubble with the first letter.
struct ForumTopicIconView: View {
    let info: ForumTopicInfo

    var body: some View {
        let color = Color(
            red: Double((info.icon.color >> 16) & 0xFF) / 255,
            green: Double((info.icon.color >> 8) & 0xFF) / 255,
            blue: Double(info.icon.color & 0xFF) / 255
        )
        ZStack {
            if info.isGeneral {
                Image(systemName: "number").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            } else {
                Circle().fill(color.gradient)
                Text(String(info.name.prefix(1)).uppercased())
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
    }
}
