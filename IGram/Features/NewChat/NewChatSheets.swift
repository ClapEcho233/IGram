//
//  NewChatSheets.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// The chat creation flows of tdesktop's main menu.
enum NewChatKind: String, Identifiable {
    case message, group, channel, secretChat, contact
    var id: String { rawValue }
}

struct NewChatSheet: View {
    let kind: NewChatKind

    var body: some View {
        switch kind {
        case .message: NewMessageSheet(isSecret: false)
        case .secretChat: NewMessageSheet(isSecret: true)
        case .group: NewGroupSheet()
        case .channel: NewChannelSheet()
        case .contact: AddContactSheet()
        }
    }
}

/// Picks a contact and opens (or creates) the private or secret chat.
private struct NewMessageSheet: View {
    let isSecret: Bool

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isSecret ? String(localized: "New Secret Chat") : String(localized: "New Message"), errorMessage: errorMessage)
            UserPickerView { userId in
                Task {
                    do {
                        let chat = isSecret
                            ? try await session.api.createNewSecretChat(userId: userId)
                            : try await session.api.createPrivateChat(force: false, userId: userId)
                        main.open(chatId: chat.id)
                        dismiss()
                    } catch {
                        errorMessage = error.telegramMessage
                    }
                }
            }
        }
        .frame(width: 400, height: 520)
    }
}

/// Members, then a title, like tdesktop's `AddParticipantsBoxController` + `GroupInfoBox`.
private struct NewGroupSheet: View {
    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.dismiss) private var dismiss
    @State private var members: Set<Int64> = []
    @State private var title = ""
    @State private var isNaming = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: isNaming ? String(localized: "New Group") : String(localized: "Add Members"), errorMessage: errorMessage) {
                if isNaming {
                    Button("Back") { isNaming = false }
                    Button("Create") { create() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                } else {
                    Button("Next") { isNaming = true }
                        .keyboardShortcut(.defaultAction)
                }
            }
            if isNaming {
                Form {
                    TextField("Group name", text: $title)
                    LabeledContent("Members", value: "\(members.count)")
                }
                .formStyle(.grouped)
            } else {
                UserPickerView(selection: $members)
            }
        }
        .frame(width: 400, height: 520)
    }

    private func create() {
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                let created = try await session.api.createNewBasicGroupChat(
                    messageAutoDeleteTime: 0,
                    title: title.trimmingCharacters(in: .whitespaces),
                    userIds: Array(members)
                )
                main.open(chatId: created.chatId)
                dismiss()
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }
}

/// Channel title and description, like tdesktop's channel `GroupInfoBox`.
private struct NewChannelSheet: View {
    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var about = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: String(localized: "New Channel"), errorMessage: errorMessage) {
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
            Form {
                TextField("Channel name", text: $title)
                TextField("Description (optional)", text: $about, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 300)
    }

    private func create() {
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                let chat = try await session.api.createNewSupergroupChat(
                    description: about,
                    forImport: false,
                    isChannel: true,
                    isForum: false,
                    location: nil,
                    messageAutoDeleteTime: 0,
                    title: title.trimmingCharacters(in: .whitespaces)
                )
                main.open(chatId: chat.id)
                dismiss()
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }
}

/// Adds a phone contact, like tdesktop's `AddContactBox`.
private struct AddContactSheet: View {
    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: String(localized: "Add Contact"), errorMessage: errorMessage) {
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(firstName.isEmpty || phone.filter(\.isNumber).count < 5)
            }
            Form {
                TextField("First name", text: $firstName)
                TextField("Last name", text: $lastName)
                TextField("Phone number", text: $phone, prompt: Text(verbatim: "+1 234 567 8900"))
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 280)
    }

    private func add() {
        Task {
            do {
                let result = try await session.api.importContacts(contacts: [ImportedContact(
                    firstName: firstName,
                    lastName: lastName,
                    note: nil,
                    phoneNumber: phone.filter { $0.isNumber || $0 == "+" }
                )])
                guard let userId = result.userIds.first, userId != 0 else {
                    errorMessage = String(localized: "\(firstName) isn't on Telegram yet.")
                    return
                }
                let chat = try await session.api.createPrivateChat(force: false, userId: userId)
                main.open(chatId: chat.id)
                dismiss()
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }
}

/// Title row with Cancel and optional trailing actions shared by the sheets.
struct SheetHeader<Actions: View>: View {
    let title: String
    var errorMessage: String?
    @ViewBuilder var actions: Actions

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(title).font(.headline)
                Spacer()
                actions
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
        }
        .padding(14)
    }
}

extension SheetHeader where Actions == EmptyView {
    init(title: String, errorMessage: String? = nil) {
        self.init(title: title, errorMessage: errorMessage) { EmptyView() }
    }
}
