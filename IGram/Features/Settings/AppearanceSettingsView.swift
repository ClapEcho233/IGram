//
//  AppearanceSettingsView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit
import UniformTypeIdentifiers

/// Theme, wallpaper and input preferences, after tdesktop's `Settings::Chat`.
struct AppearanceSettingsView: View {
    @Environment(TelegramSession.self) private var session
    @Environment(\.colorScheme) private var effectiveColorScheme
    @AppStorage(AppPreferences.colorScheme) private var colorScheme = ColorSchemePreference.system.rawValue
    @AppStorage(AppPreferences.chatPreset) private var presetValue = ChatThemePreset.default.rawValue
    @AppStorage(AppPreferences.customWallpaperPath) private var customWallpaperPath = ""
    @AppStorage(AppPreferences.customWallpaperBlurred) private var customWallpaperBlurred = false
    @AppStorage(AppPreferences.sendWithCommandReturn) private var sendWithCommandReturn = false

    @State private var isPickingWallpaper = false
    @State private var isUpdatingWallpaper = false
    @State private var errorMessage: String?

    private var isDark: Bool { effectiveColorScheme == .dark }
    private var preset: ChatThemePreset { ChatThemePreset(rawValue: presetValue) ?? .default }
    private var activeStyle: ChatThemeStyle { ChatThemeStyle(preset: preset, settings: nil, isDark: isDark) }
    private var installedBackgrounds: [Background] { session.themes.installedBackgrounds(forDarkTheme: isDark) }
    private var defaultBackgroundId: TdInt64? {
        (isDark ? session.themes.defaultDarkBackground : session.themes.defaultLightBackground)?.id
    }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Color scheme", selection: $colorScheme) {
                    ForEach(ColorSchemePreference.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    ForEach(ChatThemePreset.allCases) { item in
                        let palette = item.palette(isDark: isDark)
                        let style = ChatThemeStyle(palette: palette, isDark: isDark)
                        Button {
                            presetValue = item.rawValue
                        } label: {
                            ChatThemePreviewCard(
                                style: style,
                                background: AnyView(PresetBackgroundFill(colors: palette.backgroundColors)),
                                label: item.title,
                                isSelected: preset == item
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            Section {
                livePreview
                if !preset.usesSystemAppearance, !installedBackgrounds.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(installedBackgrounds.prefix(16)) { background in
                                Button {
                                    applyRemoteBackground(background)
                                } label: {
                                    ChatThemePreviewCard(
                                        style: activeStyle,
                                        background: AnyView(TDLibBackgroundView(background: background)),
                                        isSelected: defaultBackgroundId == background.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                HStack(spacing: 10) {
                    Button("Choose Photo…", systemImage: "photo") {
                        isPickingWallpaper = true
                    }
                    .disabled(isUpdatingWallpaper)

                    if !customWallpaperPath.isEmpty || (!preset.usesSystemAppearance && defaultBackgroundId != nil) {
                        Button("Reset to Default") {
                            resetWallpaper()
                        }
                        .disabled(isUpdatingWallpaper)
                    }

                    Spacer()
                    if isUpdatingWallpaper {
                        ProgressView().controlSize(.small)
                    }
                }

                if !customWallpaperPath.isEmpty {
                    Toggle("Blur wallpaper", isOn: $customWallpaperBlurred)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Chat Wallpaper")
            } footer: {
                if preset.usesSystemAppearance {
                    Text("The Native style draws chats on the window background, like Messages. Choose another style to use Telegram wallpapers.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Send messages with", selection: $sendWithCommandReturn) {
                    Text("Return").tag(false)
                    Text("⌘ Return").tag(true)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Keyboard")
            } footer: {
                Text(sendWithCommandReturn
                     ? "Return inserts a line break."
                     : "Shift-Return or Option-Return inserts a line break.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: isDark) {
            await session.themes.loadInstalledBackgrounds(forDarkTheme: isDark, api: session.api)
        }
        .fileImporter(isPresented: $isPickingWallpaper, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { applyCustomPhoto(url) }
        }
    }

    private var livePreview: some View {
        ZStack {
            ChatBackgroundView(chat: nil)
            VStack(spacing: 6) {
                HStack {
                    Text("Hey! How does this look?")
                        .font(.callout)
                        .foregroundStyle(activeStyle.primaryText(outgoing: false))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(activeStyle.bubbleStyle(outgoing: false), in: .rect(cornerRadius: activeStyle.isSystem ? 16 : 12, style: .continuous))
                    Spacer()
                }
                HStack {
                    Spacer()
                    Text("Looks great on macOS!")
                        .font(.callout)
                        .foregroundStyle(activeStyle.primaryText(outgoing: true))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(activeStyle.bubbleStyle(outgoing: true), in: .rect(cornerRadius: activeStyle.isSystem ? 16 : 12, style: .continuous))
                }
            }
            .padding(12)
        }
        .frame(height: 112)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    private func applyRemoteBackground(_ background: Background) {
        isUpdatingWallpaper = true
        errorMessage = nil
        Task {
            defer { isUpdatingWallpaper = false }
            do {
                _ = try await session.api.setDefaultBackground(
                    background: .inputBackgroundRemote(InputBackgroundRemote(backgroundId: background.id)),
                    forDarkTheme: isDark,
                    type: background.type
                )
            } catch {
                errorMessage = error.telegramMessage
                Log.ui.error("setDefaultBackground failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }

    private func applyCustomPhoto(_ url: URL) {
        isUpdatingWallpaper = true
        errorMessage = nil
        do {
            let saved = try LocalWallpaperStore.save(from: url)
            LocalWallpaperStore.clear(at: customWallpaperPath)
            customWallpaperPath = saved
            let blur = customWallpaperBlurred
            let dark = isDark
            Task {
                defer { isUpdatingWallpaper = false }
                // Sync to Telegram cloud when JPEG; otherwise keep local custom wallpaper.
                if url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg" {
                    _ = try? await session.api.setDefaultBackground(
                        background: .inputBackgroundLocal(InputBackgroundLocal(background: .inputFileLocal(InputFileLocal(path: saved)))),
                        forDarkTheme: dark,
                        type: .backgroundTypeWallpaper(BackgroundTypeWallpaper(isBlurred: blur, isMoving: false))
                    )
                } else {
                    _ = try? await session.api.deleteDefaultBackground(forDarkTheme: dark)
                }
            }
        } catch {
            isUpdatingWallpaper = false
            errorMessage = error.localizedDescription
        }
    }

    private func resetWallpaper() {
        isUpdatingWallpaper = true
        errorMessage = nil
        LocalWallpaperStore.clear(at: customWallpaperPath)
        customWallpaperPath = ""
        customWallpaperBlurred = false
        Task {
            defer { isUpdatingWallpaper = false }
            do {
                _ = try await session.api.deleteDefaultBackground(forDarkTheme: isDark)
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }
}
