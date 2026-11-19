//
//  ThemeStore.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// Tracks cloud chat themes (`updateEmojiChatThemes`) and default/installed
/// chat wallpapers (`updateDefaultBackground`, `getInstalledBackgrounds`),
/// mirroring tdesktop's `Window::Theme` background and cloud theme cache.
@Observable
final class ThemeStore {
    private(set) var emojiThemes: [EmojiChatTheme] = []
    private(set) var defaultLightBackground: Background?
    private(set) var defaultDarkBackground: Background?
    private(set) var installedLightBackgrounds: [Background] = []
    private(set) var installedDarkBackgrounds: [Background] = []

    /// Applies theme and default background updates from TDLib.
    @discardableResult
    func handle(_ update: Update) -> Bool {
        switch update {
        case .updateEmojiChatThemes(let value):
            emojiThemes = value.chatThemes
            return true
        case .updateDefaultBackground(let value):
            if value.forDarkTheme {
                defaultDarkBackground = value.background
            } else {
                defaultLightBackground = value.background
            }
            return true
        default:
            return false
        }
    }

    func emojiTheme(named name: String) -> EmojiChatTheme? {
        emojiThemes.first { $0.name == name }
    }

    /// The per-chat theme settings for `chat`, if a chat theme is applied.
    func themeSettings(for chat: ChatItem, isDark: Bool) -> ThemeSettings? {
        guard let theme = chat.theme else { return nil }
        switch theme {
        case .chatThemeEmoji(let value):
            guard let emoji = emojiTheme(named: value.name) else { return nil }
            return isDark ? emoji.darkSettings : emoji.lightSettings
        case .chatThemeGift(let value):
            return isDark ? value.giftTheme.darkSettings : value.giftTheme.lightSettings
        }
    }

    /// Resolves the effective TDLib background for `chat`, following Telegram's
    /// precedence: per-chat wallpaper > per-chat theme wallpaper > default wallpaper.
    func resolvedBackground(for chat: ChatItem, isDark: Bool) -> (background: Background, darkDimming: Int)? {
        if let chatBackground = chat.background {
            return (chatBackground.background, chatBackground.darkThemeDimming)
        }
        if let themeBackground = themeSettings(for: chat, isDark: isDark)?.background {
            return (themeBackground, 0)
        }
        if let defaultBackground = isDark ? defaultDarkBackground : defaultLightBackground {
            return (defaultBackground, 0)
        }
        return nil
    }

    func installedBackgrounds(forDarkTheme isDark: Bool) -> [Background] {
        isDark ? installedDarkBackgrounds : installedLightBackgrounds
    }

    func loadInstalledBackgrounds(forDarkTheme isDark: Bool, api: TDLibClient) async {
        do {
            let result = try await api.getInstalledBackgrounds(forDarkTheme: isDark)
            if isDark {
                installedDarkBackgrounds = result.backgrounds
            } else {
                installedLightBackgrounds = result.backgrounds
            }
        } catch {
            Log.data.error("getInstalledBackgrounds failed: \(error.telegramMessage, privacy: .public)")
        }
    }
}
