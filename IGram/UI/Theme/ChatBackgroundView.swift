//
//  ChatBackgroundView.swift
//  IGram
//

import AppKit
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Renders the background behind a chat's history: per-chat wallpaper, per-chat
/// theme background, TDLib cloud default wallpaper, local custom photo, or the
/// active preset gradient.
struct ChatBackgroundView: View {
    let chat: ChatItem?

    @Environment(TelegramSession.self) private var session: TelegramSession?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppPreferences.chatPreset) private var presetValue = ChatThemePreset.classic.rawValue
    @AppStorage(AppPreferences.customWallpaperPath) private var customWallpaperPath = ""
    @AppStorage(AppPreferences.customWallpaperBlurred) private var customWallpaperBlurred = false

    private var isDark: Bool { colorScheme == .dark }
    private var preset: ChatThemePreset { ChatThemePreset(rawValue: presetValue) ?? .classic }

    var body: some View {
        ZStack {
            if let chat, let resolved = session?.themes.resolvedBackground(for: chat, isDark: isDark) {
                TDLibBackgroundView(background: resolved.background, darkDimming: resolved.darkDimming)
            } else if chat == nil, let bg = isDark ? session?.themes.defaultDarkBackground : session?.themes.defaultLightBackground {
                TDLibBackgroundView(background: bg, darkDimming: 0)
            } else if let image = LocalWallpaperStore.image(at: customWallpaperPath) {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: customWallpaperBlurred ? 12 : 0, opaque: true)
                        .overlay {
                            if isDark { Color.black.opacity(0.32) }
                        }
                }
            } else {
                PresetBackgroundFill(colors: preset.palette(isDark: isDark).backgroundColors)
            }
        }
        .ignoresSafeArea()
    }
}

/// Renders one TDLib `Background` (solid, gradient, freeform mesh, pattern or photo wallpaper).
struct TDLibBackgroundView: View {
    let background: Background
    var darkDimming = 0

    @Environment(TelegramSession.self) private var session: TelegramSession?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch background.type {
        case .backgroundTypeFill(let value):
            BackgroundFillView(fill: value.fill)
                .overlay { dimmingOverlay }
        case .backgroundTypePattern(let value):
            ZStack {
                if value.isInverted {
                    Color.black
                } else {
                    BackgroundFillView(fill: value.fill)
                }
                if let document = background.document,
                   document.mimeType.lowercased().contains("png") {
                    PatternOverlay(file: document.document, fill: value.fill, intensity: value.intensity, isInverted: value.isInverted)
                }
            }
        case .backgroundTypeWallpaper(let value):
            GeometryReader { proxy in
                ZStack {
                    Color(rgb: colorScheme == .dark ? 0x0E1621 : 0xD5E3D0)
                    if let file = background.document?.document {
                        FileImage(file: file, maxPixelSize: 1600, priority: .media, contentMode: .fill) {
                            Color.clear
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: value.isBlurred ? 12 : 0, opaque: true)
                    }
                    dimmingOverlay
                }
            }
        case .backgroundTypeChatTheme(let value):
            if let emoji = session?.themes.emojiTheme(named: value.themeName),
               let referenced = (colorScheme == .dark ? emoji.darkSettings : emoji.lightSettings).background {
                TDLibBackgroundView(background: referenced, darkDimming: darkDimming)
            } else {
                PresetBackgroundFill(colors: ChatThemePreset.classic.palette(isDark: colorScheme == .dark).backgroundColors)
            }
        }
    }

    @ViewBuilder
    private var dimmingOverlay: some View {
        if colorScheme == .dark, darkDimming > 0 {
            Color.black.opacity(Double(min(max(darkDimming, 0), 100)) / 100)
        }
    }
}

/// Renders a TDLib `BackgroundFill`: solid color, angled gradient or 3–4 color freeform mesh.
struct BackgroundFillView: View {
    let fill: BackgroundFill

    var body: some View {
        switch fill {
        case .backgroundFillSolid(let value):
            Color(rgb: value.color)
        case .backgroundFillGradient(let value):
            let points = BackgroundGeometry.gradientPoints(forAngle: value.rotationAngle)
            LinearGradient(
                colors: [Color(rgb: value.topColor), Color(rgb: value.bottomColor)],
                startPoint: points.start,
                endPoint: points.end
            )
        case .backgroundFillFreeformGradient(let value):
            PresetBackgroundFill(colors: value.colors)
        }
    }
}

/// Renders 1, 2, 3 or 4 RGB colors smoothly using a GPU-accelerated `MeshGradient` when 3–4 colors are given.
struct PresetBackgroundFill: View {
    let colors: [Int]

    var body: some View {
        if colors.count >= 3 {
            let c0 = Color(rgb: colors[0])
            let c1 = Color(rgb: colors[1])
            let c2 = Color(rgb: colors[2])
            let c3 = Color(rgb: colors.count > 3 ? colors[3] : colors[1])
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
                ],
                colors: [
                    c0, c1, c2,
                    c3, c0, c1,
                    c2, c3, c0,
                ]
            )
        } else if colors.count == 2 {
            LinearGradient(
                colors: [Color(rgb: colors[0]), Color(rgb: colors[1])],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(rgb: colors.first ?? 0xD5E3D0)
        }
    }
}

private struct PatternOverlay: View {
    let file: File
    let fill: BackgroundFill
    let intensity: Int
    let isInverted: Bool

    @Environment(TelegramSession.self) private var session
    @State private var tile: CGImage?

    var body: some View {
        let item = session.files.item(for: file)
        Group {
            if let tile {
                let opacity = Double(min(max(abs(intensity), 5), 100)) / 100
                if isInverted {
                    BackgroundFillView(fill: fill)
                        .mask {
                            Image(decorative: tile, scale: 1)
                                .resizable(resizingMode: .tile)
                        }
                        .opacity(opacity)
                } else {
                    Image(decorative: tile, scale: 1)
                        .resizable(resizingMode: .tile)
                        .opacity(opacity * 0.45)
                }
            }
        }
        .task(id: item.localURL) {
            guard let url = item.localURL else {
                session.files.download(file, priority: .thumbnail)
                return
            }
            tile = await ImagePipeline.load(url, maxPixelSize: 512)
        }
    }
}

/// Miniature chat preview card showing bubbles over a theme/wallpaper swatch.
struct ChatThemePreviewCard: View {
    let style: ChatThemeStyle
    let background: AnyView
    var badge: String?
    var label: String?
    var isSelected = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                background
                VStack(spacing: 5) {
                    HStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(style.bubbleStyle(outgoing: false))
                            .frame(width: 44, height: 14)
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(style.bubbleStyle(outgoing: true))
                            .frame(width: 48, height: 14)
                    }
                }
                .padding(8)
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(5)
                }
            }
            .frame(width: 92, height: 68)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2.5 : 1)
            }
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Stores a user-picked local wallpaper photo inside Application Support so
/// sandboxed relaunches keep reading it without needing a security bookmark.
enum LocalWallpaperStore {
    static func save(from sourceURL: URL) throws -> String {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("IGram/Wallpapers", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
        let destination = directory.appendingPathComponent("custom-\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination.path(percentEncoded: false)
    }

    static func image(at path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        return NSImage(contentsOfFile: path)
    }

    static func clear(at path: String) {
        guard !path.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// Sheet to pick an emoji chat theme (or reset to default) for a specific chat.
struct ChatThemePickerSheet: View {
    let chat: ChatItem

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferences.chatPreset) private var presetValue = ChatThemePreset.classic.rawValue
    @State private var isApplying = false

    private var isDark: Bool { colorScheme == .dark }
    private var preset: ChatThemePreset { ChatThemePreset(rawValue: presetValue) ?? .classic }

    private var selectedEmojiName: String? {
        if case .chatThemeEmoji(let value) = chat.theme { return value.name }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat Theme")
                    .font(.headline)
                Spacer()
                if isApplying { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 10)], spacing: 12) {
                    defaultCard
                    ForEach(session.themes.emojiThemes, id: \.name) { theme in
                        emojiThemeCard(theme)
                    }
                }
                .padding(16)

                if chat.background != nil {
                    Divider().padding(.horizontal, 16)
                    Button("Reset Custom Chat Wallpaper", role: .destructive) {
                        resetBackground()
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: 440, height: 380)
    }

    private var defaultCard: some View {
        let palette = preset.palette(isDark: isDark)
        let style = ChatThemeStyle(palette: palette, isDark: isDark)
        return Button {
            apply(theme: nil)
        } label: {
            ChatThemePreviewCard(
                style: style,
                background: AnyView(PresetBackgroundFill(colors: palette.backgroundColors)),
                label: String(localized: "Default"),
                isSelected: chat.theme == nil
            )
        }
        .buttonStyle(.plain)
    }

    private func emojiThemeCard(_ theme: EmojiChatTheme) -> some View {
        let settings = isDark ? theme.darkSettings : theme.lightSettings
        let palette = ChatThemePalette.resolved(preset: preset, settings: settings, isDark: isDark)
        let style = ChatThemeStyle(palette: palette, isDark: isDark)
        let bgView: AnyView = if let bg = settings.background {
            AnyView(TDLibBackgroundView(background: bg))
        } else {
            AnyView(PresetBackgroundFill(colors: palette.backgroundColors))
        }
        return Button {
            apply(theme: .inputChatThemeEmoji(InputChatThemeEmoji(name: theme.name)))
        } label: {
            ChatThemePreviewCard(
                style: style,
                background: bgView,
                badge: theme.name,
                label: theme.name,
                isSelected: selectedEmojiName == theme.name
            )
        }
        .buttonStyle(.plain)
    }

    private func apply(theme: InputChatTheme?) {
        isApplying = true
        Task {
            defer { isApplying = false }
            do {
                _ = try await session.api.setChatTheme(chatId: chat.id, theme: theme)
                dismiss()
            } catch {
                main.showToast(error.telegramMessage)
                Log.ui.error("setChatTheme failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }

    private func resetBackground() {
        isApplying = true
        Task {
            defer { isApplying = false }
            do {
                _ = try await session.api.deleteChatBackground(chatId: chat.id, restorePrevious: false)
                dismiss()
            } catch {
                main.showToast(error.telegramMessage)
            }
        }
    }
}
