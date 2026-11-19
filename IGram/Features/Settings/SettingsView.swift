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
                    Tab("Appearance", systemImage: "paintbrush") {
                        AppearanceSettingsView()
                    }
                }
                .environment(session)
            } else {
                ContentUnavailableView("Not Signed In", systemImage: "person.crop.circle.badge.questionmark", description: Text("Sign in to change your settings."))
            }
        }
        .frame(width: 520, height: 460)
    }
}
