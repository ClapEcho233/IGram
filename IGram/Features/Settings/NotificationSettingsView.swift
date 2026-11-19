//
//  NotificationSettingsView.swift
//  IGram
//

import SwiftUI

/// Notification preferences, after tdesktop's `Settings::Notifications`.
struct NotificationSettingsView: View {
    @AppStorage(AppPreferences.notificationsEnabled) private var isEnabled = true
    @AppStorage(AppPreferences.notificationPreviews) private var showsPreview = true
    @AppStorage(AppPreferences.notificationSound) private var playsSound = true
    @AppStorage(AppPreferences.badgeIncludesMuted) private var badgeIncludesMuted = false

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Show notifications for new messages", isOn: $isEnabled)
                Toggle("Show message preview", isOn: $showsPreview)
                    .disabled(!isEnabled)
                Toggle("Play sound", isOn: $playsSound)
                    .disabled(!isEnabled)
            }
            Section {
                Toggle("Count messages in muted chats", isOn: $badgeIncludesMuted)
            } header: {
                Text("Dock Badge")
            } footer: {
                Text("Muted chats still notify you when you're mentioned.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
