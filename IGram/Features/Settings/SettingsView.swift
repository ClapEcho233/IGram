//
//  SettingsView.swift
//  IGram
//

import SwiftUI

/// The Settings window, with tdesktop's settings sections as tabs.
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let session = app.session, session.isAuthorized {
                TabView {
                    Tab("Account", systemImage: "person.crop.circle") {
                        AccountSettingsView()
                    }
                    Tab("Notifications", systemImage: "bell.badge") {
                        NotificationSettingsView()
                    }
                    Tab("Folders", systemImage: "folder") {
                        FoldersSettingsView()
                    }
                    Tab("Appearance", systemImage: "paintbrush") {
                        AppearanceSettingsView()
                    }
                    Tab("Privacy", systemImage: "hand.raised") {
                        PrivacySettingsView()
                    }
                    Tab("Enhancements", systemImage: "sparkles") {
                        EnhancementsSettingsView()
                    }
                    Tab("Sessions", systemImage: "laptopcomputer.and.iphone") {
                        SessionsSettingsView()
                    }
                    Tab("Proxy", systemImage: "network") {
                        ProxySettingsView()
                    }
                    Tab("Storage", systemImage: "internaldrive") {
                        StorageSettingsView()
                    }
                    Tab("Advanced", systemImage: "gearshape.2") {
                        AdvancedSettingsView()
                    }
                }
                .environment(session)
            } else {
                ContentUnavailableView("Not Signed In", systemImage: "person.crop.circle.badge.questionmark", description: Text("Sign in to change your settings."))
            }
        }
        .frame(width: 660, height: 520)
    }
}
