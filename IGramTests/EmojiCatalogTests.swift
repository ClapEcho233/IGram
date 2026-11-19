//
//  EmojiCatalogTests.swift
//  IGramTests
//

import Testing
@testable import IGram

@MainActor
struct EmojiCatalogTests {
    @Test func everySectionHasEmoji() {
        #expect(EmojiCatalog.sections.count == 8)
        for section in EmojiCatalog.sections {
            #expect(!section.emoji.isEmpty, "\(section.id) is empty")
        }
    }

    @Test func smileysComeFirst() {
        #expect(EmojiCatalog.sections[0].emoji.contains("😀"))
        #expect(EmojiCatalog.sections[1].emoji.contains("🐶"))
        #expect(EmojiCatalog.sections[2].emoji.contains("🍕"))
    }

    /// The emoji grid identifies cells by emoji within a section, so a
    /// repeated emoji would render as a blank cell.
    @Test func noDuplicatesAcrossSections() {
        let all = EmojiCatalog.sections.dropLast().flatMap(\.emoji)
        #expect(Set(all).count == all.count)
    }

    @Test func flags() {
        #expect(EmojiCatalog.flag("us") == "🇺🇸")
        #expect(EmojiCatalog.flag("1A") == nil)
        #expect(EmojiCatalog.sections.last?.emoji.contains("🇯🇵") == true)
    }
}
