//
//  ChatTheme.swift
//  IGram
//

import AppKit
import SwiftUI

/// Chat colors after tdesktop's default day and night themes.
enum ChatTheme {
    static let background = dynamic(light: 0xD5E3D0, dark: 0x0E1621)
    static let incomingBubble = dynamic(light: 0xFFFFFF, dark: 0x182533)
    static let outgoingBubble = dynamic(light: 0xEFFDDE, dark: 0x2B5278)
    static let incomingSecondary = dynamic(light: 0x8D969C, dark: 0x6D7F8F)
    static let outgoingSecondary = dynamic(light: 0x5DAE5B, dark: 0x7DA8D3)
    static let outgoingAccent = dynamic(light: 0x3FA543, dark: 0x8DC6F6)
    static let serviceBackground = dynamic(light: 0x5F7A59, dark: 0x17212B, lightAlpha: 0.55, darkAlpha: 0.85)
    static let highlight = Color.accentColor.opacity(0.18)

    static func bubble(outgoing: Bool) -> Color { outgoing ? outgoingBubble : incomingBubble }
    static func secondary(outgoing: Bool) -> Color { outgoing ? outgoingSecondary : incomingSecondary }
    static func accent(outgoing: Bool) -> Color { outgoing ? outgoingAccent : .accentColor }

    /// Builds the provider outside the main actor: AppKit may resolve dynamic
    /// colors on its rendering threads.
    nonisolated private static func dynamic(
        light: UInt32,
        dark: UInt32,
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        })
    }
}
