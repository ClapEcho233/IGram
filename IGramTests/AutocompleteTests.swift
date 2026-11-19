//
//  AutocompleteTests.swift
//  IGramTests
//

import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct AutocompleteTests {
    @Test func detectsMentions() {
        #expect(AutocompleteModel.token(in: "hi @al") == .init(kind: .mention, query: "al", length: 3))
        #expect(AutocompleteModel.token(in: "@") == .init(kind: .mention, query: "", length: 1))
        #expect(AutocompleteModel.token(in: "mail@example") == nil)
        #expect(AutocompleteModel.token(in: "hi @al ") == nil)
    }

    @Test func detectsCommands() {
        #expect(AutocompleteModel.token(in: "/st") == .init(kind: .command, query: "st", length: 3))
        #expect(AutocompleteModel.token(in: "/start now") == nil)
        #expect(AutocompleteModel.token(in: "a /st") == nil)
    }

    @Test func addsMentionEntities() {
        let text = FormattedText(entities: [TextEntity(length: 4, offset: 0, type: .textEntityTypeBold)], text: "Hey Alice Smith!")
        let result = ComposerModel.addingMentions(["Alice Smith": 7], to: text)
        #expect(result.entities.count == 2)
        #expect(result.entities[1] == TextEntity(length: 11, offset: 4, type: .textEntityTypeMentionName(TextEntityTypeMentionName(userId: 7))))
    }

    @Test func skipsOverlappingMentions() {
        let text = FormattedText(entities: [TextEntity(length: 5, offset: 0, type: .textEntityTypeBold)], text: "Alice")
        #expect(ComposerModel.addingMentions(["Alice": 7], to: text).entities.count == 1)
    }
}
