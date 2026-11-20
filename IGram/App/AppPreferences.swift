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
    static let sidebarSelection = "main.sidebarSelection"

    /// Registers defaults so unset keys read as tdesktop's defaults.
    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            colorScheme: ColorSchemePreference.system.rawValue,
            chatPreset: ChatThemePreset.default.rawValue,
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

/// The display preferences long-lived views depend on, published only when
/// their own keys change.
///
/// `@AppStorage` re-renders its view on every defaults write, including the
/// window frame and split view positions AppKit saves when windows switch
/// and the Settings tab selection, so the whole history re-rendered and
/// re-measured, jumping and flashing, on each of those.
@Observable
final class DisplayPreferences {
    static let shared = DisplayPreferences()

    private(set) var colorScheme: ColorSchemePreference
    private(set) var chatPreset: ChatThemePreset
    private(set) var customWallpaperPath: String
    private(set) var customWallpaperBlurred: Bool
    private(set) var badgeIncludesMuted: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        AppPreferences.registerDefaults(defaults)
        colorScheme = Self.colorScheme(in: defaults)
        chatPreset = Self.chatPreset(in: defaults)
        customWallpaperPath = defaults.string(forKey: AppPreferences.customWallpaperPath) ?? ""
        customWallpaperBlurred = defaults.bool(forKey: AppPreferences.customWallpaperBlurred)
        badgeIncludesMuted = defaults.bool(forKey: AppPreferences.badgeIncludesMuted)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    /// Re-reads the keys, assigning only what changed so unrelated writes
    /// don't notify observers.
    func reload() {
        let colorScheme = Self.colorScheme(in: defaults)
        if colorScheme != self.colorScheme { self.colorScheme = colorScheme }
        let preset = Self.chatPreset(in: defaults)
        if preset != chatPreset { chatPreset = preset }
        let path = defaults.string(forKey: AppPreferences.customWallpaperPath) ?? ""
        if path != customWallpaperPath { customWallpaperPath = path }
        let blurred = defaults.bool(forKey: AppPreferences.customWallpaperBlurred)
        if blurred != customWallpaperBlurred { customWallpaperBlurred = blurred }
        let muted = defaults.bool(forKey: AppPreferences.badgeIncludesMuted)
        if muted != badgeIncludesMuted { badgeIncludesMuted = muted }
    }

    private static func colorScheme(in defaults: UserDefaults) -> ColorSchemePreference {
        defaults.string(forKey: AppPreferences.colorScheme).flatMap(ColorSchemePreference.init(rawValue:)) ?? .system
    }

    private static func chatPreset(in defaults: UserDefaults) -> ChatThemePreset {
        defaults.string(forKey: AppPreferences.chatPreset).flatMap(ChatThemePreset.init(rawValue:)) ?? .default
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
