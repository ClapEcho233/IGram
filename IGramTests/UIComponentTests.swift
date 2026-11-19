//
//  UIComponentTests.swift
//  IGramTests
//

import Testing
@testable import IGram

@MainActor
struct UIComponentTests {
    @Test func initials() {
        #expect(AvatarView.initials("Pavel Durov") == "PD")
        #expect(AvatarView.initials("telegram") == "T")
        #expect(AvatarView.initials("Swift — Developers Chat") == "SC")
        #expect(AvatarView.initials("  ") == " ")
        #expect(AvatarView.initials("") == "")
        #expect(AvatarView.initials("🚀 Rocket Club") == "RC")
    }

    @Test func badgeFormatting() {
        #expect(UnreadBadge.format(7) == "7")
        #expect(UnreadBadge.format(999) == "999")
        #expect(UnreadBadge.format(1000) == "1K")
        #expect(UnreadBadge.format(1500) == "1.5K")
        #expect(UnreadBadge.format(25_000) == "25K")
    }
}
