//
//  AccountSettingsView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Profile editing, after tdesktop's `Settings::Information`.
struct AccountSettingsView: View {
    @Environment(TelegramSession.self) private var session

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var bio = ""
    @State private var username = ""
    @State private var isSaving = false
    @State private var status: String?
    @State private var didLoad = false

    var body: some View {
        let me = session.me
        Form {
            Section {
                HStack(spacing: 14) {
                    AvatarView(content: .user(me.user), size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(me.fullName).font(.title3.bold())
                        if let phone = me.user?.phoneNumber, !phone.isEmpty {
                            Text("+\(phone)").foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
            Section("Name") {
                TextField("First name", text: $firstName)
                TextField("Last name", text: $lastName)
            }
            Section {
                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Bio")
            } footer: {
                Text("Any details such as age, occupation or city. \(70 - bio.count) characters left.")
                    .foregroundStyle(bio.count > 70 ? .red : .secondary)
            }
            Section {
                TextField("Username", text: $username, prompt: Text("username"))
            } header: {
                Text("Username")
            } footer: {
                Text("People can find you by this name. You can use a–z, 0–9 and underscores; minimum length is 5 characters.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || firstName.trimmingCharacters(in: .whitespaces).isEmpty || bio.count > 70)
            }
        }
        .formStyle(.grouped)
        .task {
            guard !didLoad else { return }
            didLoad = true
            if let info = try? await session.api.getUserFullInfo(userId: session.myUserId) {
                session.peers.store(info, userId: session.myUserId)
            }
            let user = session.me.user
            firstName = user?.firstName ?? ""
            lastName = user?.lastName ?? ""
            username = user?.usernames?.editableUsername ?? ""
            bio = session.me.fullInfo?.bio?.text ?? ""
        }
    }

    private func save() {
        isSaving = true
        status = nil
        let user = session.me.user
        let currentBio = session.me.fullInfo?.bio?.text ?? ""
        Task {
            defer { isSaving = false }
            do {
                if firstName != user?.firstName || lastName != user?.lastName {
                    try await session.api.setName(firstName: firstName, lastName: lastName)
                }
                if bio != currentBio {
                    try await session.api.setBio(bio: bio)
                }
                let cleanUsername = username.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                if cleanUsername != (user?.usernames?.editableUsername ?? "") {
                    try await session.api.setUsername(username: cleanUsername)
                }
                status = String(localized: "Saved")
            } catch {
                status = error.telegramMessage
                Log.ui.error("Saving profile failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }
}
