//
//  AdvancedSettingsView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Version info, API credentials and logging out.
struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(TelegramSession.self) private var session
    @State private var tdlibVersion = ""
    @State private var isConfirmingLogOut = false
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("IGram", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                LabeledContent("TDLib", value: tdlibVersion)
                LabeledContent("API ID", value: "\(session.credentials.apiId)")
                if session.credentials.useTestDC {
                    LabeledContent("Servers", value: String(localized: "Test"))
                }
            }
            Section {
                Button("Change API Credentials…") { isConfirmingReset = true }
                    .disabled(app.credentials.isFromEnvironment)
            } footer: {
                if app.credentials.isFromEnvironment {
                    Text("Credentials come from the TG_API_ID and TG_API_HASH environment variables.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Log Out…", role: .destructive) { isConfirmingLogOut = true }
            }
        }
        .formStyle(.grouped)
        .task {
            if case .optionValueString(let value) = try? await session.api.getOption(name: "version") {
                tdlibVersion = value.value
            }
        }
        .confirmationDialog("Are you sure you want to log out?", isPresented: $isConfirmingLogOut) {
            Button("Log Out", role: .destructive) {
                Task { await session.logOut() }
            }
        } message: {
            Text("Your chats stay in the cloud. Local data on this Mac will be removed.")
        }
        .confirmationDialog("Change API credentials?", isPresented: $isConfirmingReset) {
            Button("Change", role: .destructive) { app.resetCredentials() }
        } message: {
            Text("IGram will disconnect and ask for a new API ID and hash.")
        }
    }
}
