//
//  StoriesBar.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Draws Telegram's story ring around an avatar: gradient blue for unread,
/// green for close friends, subtle gray when all stories have been viewed.
struct StoryRingOverlay: View {
    let state: StoryStore.RingState
    var lineWidth: CGFloat = 2

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .unread:
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color(rgb: 0x34AADF), Color(rgb: 0x22D68A)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: lineWidth
                )
        case .closeFriends:
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color(rgb: 0x62D950), Color(rgb: 0x26B86D)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: lineWidth
                )
        case .read:
            Circle()
                .strokeBorder(.secondary.opacity(0.4), lineWidth: max(lineWidth - 0.5, 1))
        }
    }
}

/// Horizontal strip of active stories shown above the chat list, matching
/// tdesktop's `Dialogs::Stories::List`.
struct StoriesBar: View {
    let storyList: StoryList

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main

    var body: some View {
        let items = session.stories.orderedChats(in: storyList)
        Group {
            if !items.isEmpty {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(items, id: \.chatId) { active in
                                storyCell(active, allChatIds: items.map(\.chatId))
                            }
                            if !session.stories.completedLists.contains(storyList) {
                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .task(id: items.count) {
                                        await session.stories.loadMore(storyList, api: session.api)
                                    }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    Divider()
                }
            }
        }
        .task(id: storyList) {
            await session.stories.loadMore(storyList, api: session.api)
        }
    }

    private func storyCell(_ active: ChatActiveStories, allChatIds: [Int64]) -> some View {
        let chat = session.chats.chat(active.chatId)
        let ring = StoryStore.ringState(for: active)
        let title = displayName(for: active.chatId, chat: chat)
        return Button {
            main.openStories(chatIds: allChatIds, startingAt: active.chatId)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    avatar(for: active.chatId, chat: chat)
                    StoryRingOverlay(state: ring, lineWidth: 2.2)
                        .frame(width: 50, height: 50)
                }
                .frame(width: 50, height: 50)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(ring == .read ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(width: 56)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    @ViewBuilder
    private func avatar(for chatId: Int64, chat: ChatItem?) -> some View {
        if let chat {
            AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 42)
        } else {
            AvatarView(content: .user(session.peers.user(chatId).user), size: 42)
        }
    }

    private func displayName(for chatId: Int64, chat: ChatItem?) -> String {
        if let chat {
            if session.isSavedMessages(chat) { return String(localized: "My Story") }
            if let userId = chat.userId, let first = session.peers.user(userId).user?.firstName, !first.isEmpty {
                return first
            }
            return session.title(of: chat)
        }
        if chatId == session.myUserId { return String(localized: "My Story") }
        let user = session.peers.user(chatId).user
        if let first = user?.firstName, !first.isEmpty { return first }
        return session.userName(chatId)
    }
}
