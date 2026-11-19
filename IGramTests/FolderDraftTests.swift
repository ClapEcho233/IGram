//
//  FolderDraftTests.swift
//  IGramTests
//

import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct FolderDraftTests {
    @Test func emptyDraftNeedsChats() {
        var draft = FolderDraft()
        #expect(draft.isEmpty)
        draft.includeGroups = true
        #expect(!draft.isEmpty)
    }

    @Test func roundTripsThroughChatFolder() {
        var draft = FolderDraft()
        draft.name = "Work"
        draft.includeGroups = true
        draft.excludeMuted = true
        draft.includedChatIds = [1, 2]
        draft.pinnedChatIds = [2, 9]
        let folder = draft.folder
        #expect(folder.name.text.text == "Work")
        #expect(folder.includeGroups && folder.excludeMuted)
        #expect(folder.pinnedChatIds == [2])

        let copy = FolderDraft(id: 4, folder: folder)
        #expect(copy.id == 4)
        #expect(copy.includedChatIds == [1, 2])
        #expect(copy.folder == folder)
    }
}
