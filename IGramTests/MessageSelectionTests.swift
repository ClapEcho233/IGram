//
//  MessageSelectionTests.swift
//  IGramTests
//

import Testing
@testable import IGram

@MainActor
struct MessageSelectionTests {
    @Test func togglesSingleMessages() {
        let actions = MessageActionsModel()
        #expect(!actions.isSelecting)
        actions.toggleSelection(of: [5])
        #expect(actions.selectedIds == [5])
        actions.toggleSelection(of: [5])
        #expect(!actions.isSelecting)
    }

    @Test func albumsToggleTogether() {
        let actions = MessageActionsModel()
        actions.toggleSelection(of: [1])
        actions.toggleSelection(of: [1, 2, 3])
        #expect(actions.selectedIds == [1, 2, 3])
        actions.toggleSelection(of: [1, 2, 3])
        #expect(actions.selectedIds.isEmpty)
    }

    @Test func clearSelection() {
        let actions = MessageActionsModel()
        actions.toggleSelection(of: [1, 2])
        actions.clearSelection()
        #expect(!actions.isSelecting)
    }
}
