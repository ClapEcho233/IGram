//
//  StoryStore.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// Tracks active stories per chat and cached full `Story` payloads, mirroring
/// tdesktop's `Data::Stories`.
@Observable
final class StoryStore {
    struct StoryKey: Hashable, Sendable {
        let posterChatId: Int64
        let storyId: Int
    }

    enum RingState: Equatable, Sendable {
        case none
        case read
        case unread
        case closeFriends
    }

    private(set) var activeByChat: [Int64: ChatActiveStories] = [:]
    private(set) var stories: [StoryKey: Story] = [:]
    private(set) var totalCount: [StoryList: Int] = [:]
    private(set) var completedLists: Set<StoryList> = []
    @ObservationIgnored private var loadingLists: Set<StoryList> = []

    @discardableResult
    func handle(_ update: Update) -> Bool {
        switch update {
        case .updateChatActiveStories(let value):
            let active = value.activeStories
            if active.stories.isEmpty {
                activeByChat[active.chatId] = nil
            } else {
                activeByChat[active.chatId] = active
            }
            return true
        case .updateStory(let value):
            let story = value.story
            stories[StoryKey(posterChatId: story.posterChatId, storyId: story.id)] = story
            return true
        case .updateStoryDeleted(let value):
            let key = StoryKey(posterChatId: value.storyPosterChatId, storyId: value.storyId)
            stories[key] = nil
            if let existing = activeByChat[value.storyPosterChatId] {
                let remaining = existing.stories.filter { $0.storyId != value.storyId }
                if remaining.isEmpty {
                    activeByChat[value.storyPosterChatId] = nil
                } else {
                    activeByChat[value.storyPosterChatId] = ChatActiveStories(
                        canBeArchived: existing.canBeArchived,
                        chatId: existing.chatId,
                        list: existing.list,
                        maxReadStoryId: existing.maxReadStoryId,
                        order: existing.order,
                        stories: remaining
                    )
                }
            }
            return true
        case .updateStoryListChatCount(let value):
            totalCount[value.storyList] = value.chatCount
            return true
        default:
            return false
        }
    }

    /// Active story feeds in `list`, ordered by `(order, chatId)` descending per TDLib spec.
    func orderedChats(in list: StoryList) -> [ChatActiveStories] {
        activeByChat.values
            .filter { $0.list == list && $0.order > 0 && !$0.stories.isEmpty }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order > rhs.order }
                return lhs.chatId > rhs.chatId
            }
    }

    func activeStories(for chatId: Int64) -> ChatActiveStories? {
        guard let active = activeByChat[chatId], !active.stories.isEmpty else { return nil }
        return active
    }

    func ringState(for chatId: Int64) -> RingState {
        guard let active = activeStories(for: chatId) else { return .none }
        return Self.ringState(for: active)
    }

    nonisolated static func ringState(for active: ChatActiveStories) -> RingState {
        guard !active.stories.isEmpty else { return .none }
        let unread = active.stories.filter { $0.storyId > active.maxReadStoryId }
        guard !unread.isEmpty else { return .read }
        return unread.contains(where: \.isForCloseFriends) ? .closeFriends : .unread
    }

    /// Index of the first unread story, or 0 when all have been viewed.
    nonisolated static func firstUnreadIndex(in active: ChatActiveStories) -> Int {
        active.stories.firstIndex { $0.storyId > active.maxReadStoryId } ?? 0
    }

    func cachedStory(posterChatId: Int64, storyId: Int) -> Story? {
        stories[StoryKey(posterChatId: posterChatId, storyId: storyId)]
    }

    func loadMore(_ list: StoryList, api: TDLibClient) async {
        guard !completedLists.contains(list), !loadingLists.contains(list) else { return }
        loadingLists.insert(list)
        defer { loadingLists.remove(list) }
        do {
            _ = try await api.loadActiveStories(storyList: list)
        } catch let error as TDError where error.code == 404 {
            completedLists.insert(list)
        } catch {
            Log.data.error("loadActiveStories failed: \(error.telegramMessage, privacy: .public)")
        }
    }

    func fetchStory(posterChatId: Int64, storyId: Int, api: TDLibClient) async -> Story? {
        let key = StoryKey(posterChatId: posterChatId, storyId: storyId)
        if let cached = stories[key] { return cached }
        do {
            let fetched = try await api.getStory(onlyLocal: false, storyId: storyId, storyPosterChatId: posterChatId)
            stories[key] = fetched
            return fetched
        } catch {
            Log.data.error("getStory failed: \(error.telegramMessage, privacy: .public)")
            return nil
        }
    }
}
