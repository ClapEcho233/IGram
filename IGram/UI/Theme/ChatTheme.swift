//
//  ChatTheme.swift
//  IGram
//

import AppKit
import SwiftUI
@preconcurrency import TDLibKit

/// Built-in chat palettes after tdesktop's Classic, Day, Tinted and Arctic themes.
enum ChatThemePreset: String, CaseIterable, Identifiable, Sendable {
    case classic
    case day
    case tinted
    case arctic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .day: String(localized: "Day Blue")
        case .tinted: String(localized: "Tinted")
        case .arctic: String(localized: "Arctic")
        }
    }

    var lightPalette: ChatThemePalette {
        switch self {
        case .classic:
            ChatThemePalette(
                backgroundColors: [0xD5E3D0, 0xC6DCB8, 0xDCE8CD],
                incomingBubble: 0xFFFFFF,
                outgoingBubble: .solid(0xEFFDDE),
                incomingSecondary: 0x8D969C,
                outgoingSecondary: 0x5DAE5B,
                incomingAccent: 0x168ACD,
                outgoingAccent: 0x3FA543
            )
        case .day:
            ChatThemePalette(
                backgroundColors: [0xE6ECF2, 0xD8E4F0, 0xECF2F8],
                incomingBubble: 0xFFFFFF,
                outgoingBubble: .gradient(top: 0x3A97E0, bottom: 0x2B82CC, angle: 135),
                incomingSecondary: 0x8D969C,
                outgoingSecondary: 0xD6EEFF,
                incomingAccent: 0x168ACD,
                outgoingAccent: 0xFFFFFF
            )
        case .tinted:
            ChatThemePalette(
                backgroundColors: [0xDCE4F2, 0xCFD8EC, 0xE6E4F4],
                incomingBubble: 0xFFFFFF,
                outgoingBubble: .gradient(top: 0x6A7CE6, bottom: 0x5664D2, angle: 135),
                incomingSecondary: 0x8A93A2,
                outgoingSecondary: 0xE0E5FF,
                incomingAccent: 0x5865D6,
                outgoingAccent: 0xFFFFFF
            )
        case .arctic:
            ChatThemePalette(
                backgroundColors: [0xEFEFF4],
                incomingBubble: 0xFFFFFF,
                outgoingBubble: .solid(0xE1ECF7),
                incomingSecondary: 0x8E8E93,
                outgoingSecondary: 0x5E7A96,
                incomingAccent: 0x007AFF,
                outgoingAccent: 0x0A66C2
            )
        }
    }

    var darkPalette: ChatThemePalette {
        switch self {
        case .classic:
            ChatThemePalette(
                backgroundColors: [0x0E1621],
                incomingBubble: 0x182533,
                outgoingBubble: .solid(0x2B5278),
                incomingSecondary: 0x6D7F8F,
                outgoingSecondary: 0x7DA8D3,
                incomingAccent: 0x6AB2F2,
                outgoingAccent: 0x8DC6F6
            )
        case .day:
            ChatThemePalette(
                backgroundColors: [0x0D1520, 0x132234],
                incomingBubble: 0x182635,
                outgoingBubble: .gradient(top: 0x2F6EA5, bottom: 0x245687, angle: 135),
                incomingSecondary: 0x6D7F8F,
                outgoingSecondary: 0x99C4E8,
                incomingAccent: 0x6AB2F2,
                outgoingAccent: 0x9FD2FF
            )
        case .tinted:
            ChatThemePalette(
                backgroundColors: [0x151B28, 0x1E263B, 0x1A2034],
                incomingBubble: 0x20293E,
                outgoingBubble: .gradient(top: 0x4E5BBE, bottom: 0x3A459E, angle: 135),
                incomingSecondary: 0x7C88A5,
                outgoingSecondary: 0xC6CEFF,
                incomingAccent: 0x8E9BFF,
                outgoingAccent: 0xC8D0FF
            )
        case .arctic:
            ChatThemePalette(
                backgroundColors: [0x121214],
                incomingBubble: 0x1F1F23,
                outgoingBubble: .solid(0x32323A),
                incomingSecondary: 0x8E8E93,
                outgoingSecondary: 0xA8A8B2,
                incomingAccent: 0x5AC8FA,
                outgoingAccent: 0x8CD8FF
            )
        }
    }

    func palette(isDark: Bool) -> ChatThemePalette {
        isDark ? darkPalette : lightPalette
    }
}

/// Fill for an outgoing message bubble: either a single RGB color or a gradient.
nonisolated enum OutgoingBubbleFill: Equatable, Sendable {
    case solid(Int)
    case gradient(top: Int, bottom: Int, angle: Int)
    case freeform([Int])

    /// Representative RGB value used to compute text legibility contrast.
    var representativeRGB: Int {
        switch self {
        case .solid(let rgb): rgb
        case .gradient(let top, _, _): top
        case .freeform(let colors): colors.first ?? 0x2B5278
        }
    }

    static func from(_ fill: BackgroundFill) -> OutgoingBubbleFill {
        switch fill {
        case .backgroundFillSolid(let value):
            .solid(value.color & 0xFFFFFF)
        case .backgroundFillGradient(let value):
            .gradient(top: value.topColor & 0xFFFFFF, bottom: value.bottomColor & 0xFFFFFF, angle: value.rotationAngle)
        case .backgroundFillFreeformGradient(let value):
            .freeform(value.colors.map { $0 & 0xFFFFFF })
        }
    }
}

/// Pure RGB specification of a chat palette, testable without AppKit.
nonisolated struct ChatThemePalette: Equatable, Sendable {
    let backgroundColors: [Int]
    let incomingBubble: Int
    let outgoingBubble: OutgoingBubbleFill
    let incomingSecondary: Int
    let outgoingSecondary: Int
    let incomingAccent: Int
    let outgoingAccent: Int

    /// True when outgoing message text should be white rather than primary dark text.
    var outgoingNeedsLightText: Bool {
        Self.isDarkColor(outgoingBubble.representativeRGB)
    }

    /// Relative luminance check (BT.709) to pick crisp foreground contrast.
    static func isDarkColor(_ rgb: Int) -> Bool {
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance < 0.62
    }

    /// Merges a TDLib per-chat `ThemeSettings` onto a base preset palette.
    static func resolved(preset: ChatThemePreset, settings: ThemeSettings?, isDark: Bool) -> ChatThemePalette {
        let base = preset.palette(isDark: isDark)
        guard let settings else { return base }
        let accent = settings.accentColor & 0xFFFFFF
        let outgoingFill = settings.outgoingMessageFill.map(OutgoingBubbleFill.from) ?? base.outgoingBubble
        let outgoingIsDark = Self.isDarkColor(outgoingFill.representativeRGB)
        let outgoingAccent: Int
        if settings.hasOutgoingMessageAccentColor {
            outgoingAccent = settings.outgoingMessageAccentColor & 0xFFFFFF
        } else if outgoingIsDark {
            outgoingAccent = isDark ? accent : 0xFFFFFF
        } else {
            outgoingAccent = accent
        }
        let outgoingSecondary = outgoingIsDark ? (isDark ? 0xB8C7D9 : 0xE6F2FF) : base.outgoingSecondary
        return ChatThemePalette(
            backgroundColors: base.backgroundColors,
            incomingBubble: base.incomingBubble,
            outgoingBubble: outgoingFill,
            incomingSecondary: base.incomingSecondary,
            outgoingSecondary: outgoingSecondary,
            incomingAccent: accent,
            outgoingAccent: outgoingAccent
        )
    }
}

/// Geometry helper converting TDLib's clockwise gradient rotation angle into SwiftUI unit points.
nonisolated enum BackgroundGeometry {
    static func gradientPoints(forAngle degrees: Int) -> (start: UnitPoint, end: UnitPoint) {
        let normalized = ((degrees % 360) + 360) % 360
        let radians = Double(normalized) * .pi / 180
        // 0° points straight down (top -> bottom); 90° points left -> right.
        let dx = sin(radians) * 0.5
        let dy = cos(radians) * 0.5
        return (
            start: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
            end: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
        )
    }
}

/// Active theme resolved for a chat and passed down via SwiftUI's environment.
struct ChatThemeStyle: Equatable {
    let palette: ChatThemePalette
    let isDark: Bool

    static let `default` = ChatThemeStyle(palette: ChatThemePreset.classic.lightPalette, isDark: false)

    func bubbleStyle(outgoing: Bool) -> AnyShapeStyle {
        guard outgoing else { return AnyShapeStyle(Color(rgb: palette.incomingBubble)) }
        switch palette.outgoingBubble {
        case .solid(let rgb):
            return AnyShapeStyle(Color(rgb: rgb))
        case .gradient(let top, let bottom, let angle):
            let points = BackgroundGeometry.gradientPoints(forAngle: angle)
            return AnyShapeStyle(LinearGradient(
                colors: [Color(rgb: top), Color(rgb: bottom)],
                startPoint: points.start,
                endPoint: points.end
            ))
        case .freeform(let colors):
            let resolved = colors.isEmpty ? [Color(rgb: 0x2B5278)] : colors.map { Color(rgb: $0) }
            return AnyShapeStyle(LinearGradient(colors: resolved, startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    func primaryText(outgoing: Bool) -> Color {
        guard outgoing else { return .primary }
        return palette.outgoingNeedsLightText ? .white : Color(rgb: 0x111111)
    }

    func secondary(outgoing: Bool) -> Color {
        Color(rgb: outgoing ? palette.outgoingSecondary : palette.incomingSecondary)
    }

    func accent(outgoing: Bool) -> Color {
        Color(rgb: outgoing ? palette.outgoingAccent : palette.incomingAccent)
    }
}

extension EnvironmentValues {
    @Entry var chatThemeStyle: ChatThemeStyle = .default
}

/// Chat colors after tdesktop's default day and night themes (static fallbacks).
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
