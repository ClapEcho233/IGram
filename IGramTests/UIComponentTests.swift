//
//  UIComponentTests.swift
//  IGramTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
@preconcurrency import TDLibKit
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

    /// Bubbles used to be laid out at their single-line width and overflowed
    /// their rows, so long messages overlapped the next ones.
    @Test func bubbleWidthHugsShortTextAndWrapsLongText() {
        let short = NSHostingView(rootView: HuggingWidthLayout(maxWidth: 200) { Text("Hi") })
        #expect(short.fittingSize.width < 60)

        let long = NSHostingView(rootView: HuggingWidthLayout(maxWidth: 200) {
            Text(String(repeating: "wrap this message ", count: 30))
        })
        #expect(long.fittingSize.width <= 200)
        #expect(long.fittingSize.height > 60)
    }

    @Test func captionWrapsToMediaWidth() {
        let stack = NSHostingView(rootView: FirstChildWidthStack(spacing: 4) {
            Color.red.frame(width: 120, height: 80)
            Text(String(repeating: "caption ", count: 40))
        })
        #expect(stack.fittingSize.width == 120)
        #expect(stack.fittingSize.height > 120)
    }
}

@MainActor
struct LinkRouterTests {
    @Test func extractsUsernamesFromTelegramLinks() {
        #expect(LinkRouter.telegramUsername(from: URL(string: "https://t.me/durov")!) == "durov")
        #expect(LinkRouter.telegramUsername(from: URL(string: "https://telegram.me/swift")!) == "swift")
        #expect(LinkRouter.telegramUsername(from: URL(string: "https://t.me/+AbCdEf")!) == nil)
        #expect(LinkRouter.telegramUsername(from: URL(string: "https://t.me/joinchat")!) == nil)
        #expect(LinkRouter.telegramUsername(from: URL(string: "https://t.me/durov/123")!) == nil)
        #expect(LinkRouter.telegramUsername(from: URL(string: "https://t.me/bot?start=abc")!) == nil)
        #expect(LinkRouter.telegramUsername(from: URL(string: "https://example.com/durov")!) == nil)
    }

    @Test func detectsTelegramDeepLinks() {
        #expect(LinkRouter.isTelegramURL(URL(string: "https://t.me/+AbCdEf")!))
        #expect(LinkRouter.isTelegramURL(URL(string: "https://t.me/addstickers/Animals")!))
        #expect(LinkRouter.isTelegramURL(URL(string: "https://telegram.dog/durov/123")!))
        #expect(LinkRouter.isTelegramURL(URL(string: "tg://resolve?domain=durov")!))
        #expect(!LinkRouter.isTelegramURL(URL(string: "https://apple.com")!))
    }
}

@MainActor
struct ReactionTests {
    @Test func symbols() {
        #expect(ReactionActions.symbol(for: .reactionTypeEmoji(ReactionTypeEmoji(emoji: "🔥"))) == "🔥")
        #expect(ReactionActions.symbol(for: .reactionTypePaid) == "⭐️")
    }
}
