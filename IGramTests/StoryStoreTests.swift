//
//  StoryStoreTests.swift
//  IGramTests
//

import Foundation
import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct StoryStoreTests {
    private func storyInfo(id: Int, closeFriends: Bool = false) -> StoryInfo {
        StoryInfo(date: 1_700_000_000 + id, isForCloseFriends: closeFriends, isLive: false, storyId: id)
    }

    private func active(
        chatId: Int64,
        order: Int64,
        list: StoryList? = .storyListMain,
        maxRead: Int = 0,
        stories: [StoryInfo]
    ) -> ChatActiveStories {
        ChatActiveStories(
            canBeArchived: true,
            chatId: chatId,
            list: list,
            maxReadStoryId: maxRead,
            order: order,
            stories: stories
        )
    }

    private func makeStory(chatId: Int64, id: Int) -> Story {
        Story(
            albumIds: [], areas: [], canBeAddedToAlbum: false, canBeDeleted: true, canBeEdited: false,
            canBeForwarded: true, canBeReplied: true, canGetInteractions: false, canGetStatistics: false,
            canSetPrivacySettings: false, canToggleIsPostedToChatPage: false,
            caption: FormattedText(entities: [], text: "Hello"),
            chosenReactionType: nil,
            content: .storyContentUnsupported,
            date: 1_700_000_000,
            hasExpiredViewers: false,
            id: id,
            interactionInfo: nil,
            isBeingEdited: false,
            isBeingPosted: false,
            isEdited: false,
            isPostedToChatPage: false,
            isVisibleOnlyForSelf: false,
            music: nil,
            posterChatId: chatId,
            posterId: nil,
            privacySettings: .storyPrivacySettingsEveryone(StoryPrivacySettingsEveryone(exceptUserIds: [])),
            repostInfo: nil
        )
    }

    @Test func ordersChatsByOrderAndChatIdDescendingPerList() {
        let store = StoryStore()
        store.handle(.updateChatActiveStories(UpdateChatActiveStories(
            activeStories: active(chatId: 10, order: 100, stories: [storyInfo(id: 1)])
        )))
        store.handle(.updateChatActiveStories(UpdateChatActiveStories(
            activeStories: active(chatId: 20, order: 100, stories: [storyInfo(id: 2)])
        )))
        store.handle(.updateChatActiveStories(UpdateChatActiveStories(
            activeStories: active(chatId: 5, order: 200, stories: [storyInfo(id: 3)])
        )))
        store.handle(.updateChatActiveStories(UpdateChatActiveStories(
            activeStories: active(chatId: 30, order: 500, list: .storyListArchive, stories: [storyInfo(id: 4)])
        )))
        store.handle(.updateChatActiveStories(UpdateChatActiveStories(
            activeStories: active(chatId: 40, order: 0, stories: [storyInfo(id: 5)])
        )))

        #expect(store.orderedChats(in: .storyListMain).map(\.chatId) == [5, 20, 10])
        #expect(store.orderedChats(in: .storyListArchive).map(\.chatId) == [30])
    }

    @Test func computesRingStateAndFirstUnreadIndex() {
        let unread = active(chatId: 1, order: 10, maxRead: 2, stories: [storyInfo(id: 1), storyInfo(id: 2), storyInfo(id: 5)])
        #expect(StoryStore.ringState(for: unread) == .unread)
        #expect(StoryStore.firstUnreadIndex(in: unread) == 2)

        let closeFriends = active(chatId: 2, order: 10, maxRead: 1, stories: [storyInfo(id: 1), storyInfo(id: 3, closeFriends: true)])
        #expect(StoryStore.ringState(for: closeFriends) == .closeFriends)
        #expect(StoryStore.firstUnreadIndex(in: closeFriends) == 1)

        let read = active(chatId: 3, order: 10, maxRead: 5, stories: [storyInfo(id: 1), storyInfo(id: 5)])
        #expect(StoryStore.ringState(for: read) == .read)
        #expect(StoryStore.firstUnreadIndex(in: read) == 0)
    }

    @Test func cachesAndDeletesStories() {
        let store = StoryStore()
        store.handle(.updateChatActiveStories(UpdateChatActiveStories(
            activeStories: active(chatId: 7, order: 10, stories: [storyInfo(id: 1), storyInfo(id: 2)])
        )))
        store.handle(.updateStory(UpdateStory(story: makeStory(chatId: 7, id: 1))))
        #expect(store.cachedStory(posterChatId: 7, storyId: 1)?.id == 1)
        #expect(store.ringState(for: 7) == .unread)

        store.handle(.updateStoryDeleted(UpdateStoryDeleted(storyId: 1, storyPosterChatId: 7)))
        #expect(store.cachedStory(posterChatId: 7, storyId: 1) == nil)
        #expect(store.activeStories(for: 7)?.stories.map(\.storyId) == [2])

        store.handle(.updateStoryDeleted(UpdateStoryDeleted(storyId: 2, storyPosterChatId: 7)))
        #expect(store.activeStories(for: 7) == nil)
        #expect(store.ringState(for: 7) == .none)
    }
}
