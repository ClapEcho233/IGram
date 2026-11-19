//
//  AppPreferences.swift
//  IGram
//

import SwiftUI

/// Local preferences stored in `UserDefaults`, like tdesktop's `Core::Settings`.
enum AppPreferences {
    static let colorScheme = "appearance.colorScheme"
    static let chatPreset = "appearance.chatPreset"
    static let customWallpaperPath = "appearance.customWallpaperPath"
    static let customWallpaperBlurred = "appearance.customWallpaperBlurred"
    static let sendWithCommandReturn = "composer.sendWithCommandReturn"
    static let notificationsEnabled = "notifications.enabled"
    static let notificationPreviews = "notifications.showPreview"
    static let notificationSound = "notifications.sound"
    static let badgeIncludesMuted = "badge.includesMuted"

    /// Registers defaults so unset keys read as tdesktop's defaults.
    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            colorScheme: ColorSchemePreference.system.rawValue,
            chatPreset: ChatThemePreset.classic.rawValue,
            customWallpaperPath: "",
            customWallpaperBlurred: false,
            sendWithCommandReturn: false,
            notificationsEnabled: true,
            notificationPreviews: true,
            notificationSound: true,
            badgeIncludesMuted: false,
        ])
    }
}

enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Day")
        case .dark: String(localized: "Night")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
