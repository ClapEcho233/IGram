//
//  AppearanceSettingsView.swift
//  IGram
//

import SwiftUI

/// Theme and input preferences, after tdesktop's `Settings::Chat`.
struct AppearanceSettingsView: View {
    @AppStorage(AppPreferences.colorScheme) private var colorScheme = ColorSchemePreference.system.rawValue
    @AppStorage(AppPreferences.sendWithCommandReturn) private var sendWithCommandReturn = false

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Color scheme", selection: $colorScheme) {
                    ForEach(ColorSchemePreference.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
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
    }
}
