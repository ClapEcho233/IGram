//
//  ChatFolderStoreTests.swift
//  IGramTests
//

import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct ChatFolderStoreTests {
    private func folder(_ id: Int, _ name: String, icon: String = "Custom") -> ChatFolderInfo {
        ChatFolderInfo(
            colorId: -1,
            hasMyInviteLinks: false,
            icon: ChatFolderIcon(name: icon),
            id: id,
            isShareable: false,
            name: ChatFolderName(animateCustomEmoji: false, text: FormattedText(entities: [], text: name))
        )
    }

    @Test func noFoldersMeansNoTabs() {
        #expect(ChatFolderStore.tabs(folders: [], mainChatListPosition: 0).isEmpty)
    }

    @Test func allChatsFirstByDefault() {
        let tabs = ChatFolderStore.tabs(folders: [folder(1, "Work"), folder(2, "Family")], mainChatListPosition: 0)
        #expect(tabs.map(\.id) == [-1, 1, 2])
        #expect(tabs.first?.chatList == .chatListMain)
    }

    @Test func allChatsAtRequestedPosition() {
        let tabs = ChatFolderStore.tabs(folders: [folder(1, "Work"), folder(2, "Family")], mainChatListPosition: 1)
        #expect(tabs.map(\.id) == [1, -1, 2])
    }

    @Test func positionIsClamped() {
        let tabs = ChatFolderStore.tabs(folders: [folder(1, "Work")], mainChatListPosition: 9)
        #expect(tabs.map(\.id) == [1, -1])
    }

    @Test func folderTabProperties() {
        let tab = ChatFolderTab.folder(folder(3, "Bots", icon: "Bots"))
        #expect(tab.title == "Bots")
        #expect(tab.systemImage == "cpu")
        #expect(tab.chatList == .chatListFolder(ChatListFolder(chatFolderId: 3)))
    }

    @Test func appliesUpdate() {
        let store = ChatFolderStore()
        let handled = store.handle(.updateChatFolders(UpdateChatFolders(
            areTagsEnabled: true,
            chatFolders: [folder(1, "Work")],
            mainChatListPosition: 1
        )))
        #expect(handled)
        #expect(store.folders.count == 1)
        #expect(store.mainChatListPosition == 1)
        #expect(store.areTagsEnabled)
        #expect(!store.handle(.updateOption(UpdateOption(name: "x", value: .optionValueEmpty))))
    }
}
