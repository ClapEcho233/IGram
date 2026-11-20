//
//  EditChatSheet.swift
//  IGram
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import TDLibKit

/// Group and channel settings, after tdesktop's `EditPeerInfoBox`.
struct EditChatSheet: View {
    let chat: ChatItem

    @Environment(TelegramSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var about = ""
    @State private var username = ""
    @State private var allHistoryVisible = true
    @State private var signMessages = false
    @State private var autoDelete = 0
    @State private var permissions: ChatPermissions?
    @State private var isPickingPhoto = false
    @State private var isSaving = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    private var supergroup: SupergroupItem? {
        if case .chatTypeSupergroup(let value) = chat.type { return session.peers.supergroup(value.supergroupId) }
        return nil
    }

    private var inviteLink: String? {
        switch chat.type {
        case .chatTypeBasicGroup(let value): session.peers.basicGroup(value.basicGroupId).fullInfo?.inviteLink?.inviteLink
        case .chatTypeSupergroup(let value): session.peers.supergroup(value.supergroupId).fullInfo?.inviteLink?.inviteLink
        default: nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: chat.isChannel ? String(localized: "Edit Channel") : String(localized: "Edit Group"), errorMessage: errorMessage) {
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Form {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 64)
                        VStack(alignment: .leading) {
                            Button("Set New Photo…") { isPickingPhoto = true }
                            if chat.photo != nil {
                                Button("Remove Photo", role: .destructive) { setPhoto(nil) }
                            }
                        }
                        .buttonStyle(.link)
                    }
                    TextField(chat.isChannel ? "Channel name" : "Group name", text: $title)
                    TextField("Description", text: $about, axis: .vertical)
                        .lineLimit(2...5)
                }
                if supergroup != nil {
                    Section {
                        LabeledContent("t.me/") {
                            TextField("Public link", text: $username, prompt: Text("username"))
                                .labelsHidden()
                        }
                    } header: {
                        Text(chat.isChannel ? "Channel Type" : "Group Type")
                    } footer: {
                        Text(username.isEmpty
                             ? "Private: people can only join by invite link."
                             : "Public: anyone can find and join through the link.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let inviteLink {
                    Section("Invite Link") {
                        Text(inviteLink).textSelection(.enabled)
                        HStack {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(inviteLink, forType: .string)
                            }
                            Button("Revoke", role: .destructive) { revokeLink() }
                        }
                    }
                }
                Section {
                    if chat.isChannel {
                        Toggle("Sign messages", isOn: $signMessages)
                    } else if supergroup != nil {
                        Toggle("Chat history visible to new members", isOn: $allHistoryVisible)
                    }
                    Picker("Auto-delete messages", selection: $autoDelete) {
                        Text("Off").tag(0)
                        Text("After 1 day").tag(86_400)
                        Text("After 1 week").tag(604_800)
                        Text("After 1 month").tag(2_678_400)
                    }
                }
                if !chat.isChannel, let permissions {
                    Section("What Members Can Do") {
                        permissionToggle("Send messages", \.canSendBasicMessages, permissions)
                        permissionToggle("Send photos and videos", \.canSendPhotos, permissions)
                        permissionToggle("Send stickers and GIFs", \.canSendOtherMessages, permissions)
                        permissionToggle("Add members", \.canInviteUsers, permissions)
                        permissionToggle("Pin messages", \.canPinMessages, permissions)
                        permissionToggle("Change group info", \.canChangeInfo, permissions)
                    }
                }
                if session.isCreator(of: chat) {
                    Section {
                        Button(chat.isChannel ? "Delete Channel" : "Delete Group", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 460, height: 620)
        .task { load() }
        .fileImporter(isPresented: $isPickingPhoto, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                Task {
                    if let copy = await AttachmentPreparer.prepare([url]).first { setPhoto(copy.url) }
                }
            }
        }
        .confirmationDialog(chat.isChannel ? "Delete this channel for everyone?" : "Delete this group for everyone?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    session.archive.expectHistoryCleared(chatId: chat.id)
                    _ = try? await session.api.deleteChat(chatId: chat.id)
                    dismiss()
                }
            }
        }
    }

    private func permissionToggle(_ title: LocalizedStringKey, _ keyPath: KeyPath<ChatPermissions, Bool>, _ current: ChatPermissions) -> some View {
        Toggle(title, isOn: Binding(
            get: { current[keyPath: keyPath] },
            set: { value in
                var updated = current.with(keyPath, value)
                if keyPath == \.canSendPhotos {
                    updated = updated.with(\.canSendVideos, value).with(\.canSendDocuments, value)
                }
                permissions = updated
            }
        ))
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        title = chat.title
        autoDelete = chat.messageAutoDeleteTime
        permissions = chat.permissions
        switch chat.type {
        case .chatTypeBasicGroup(let value):
            about = session.peers.basicGroup(value.basicGroupId).fullInfo?.description ?? ""
        case .chatTypeSupergroup:
            about = supergroup?.fullInfo?.description ?? ""
            username = supergroup?.supergroup?.usernames?.editableUsername ?? ""
            allHistoryVisible = supergroup?.fullInfo?.isAllHistoryAvailable ?? true
            signMessages = supergroup?.supergroup?.signMessages ?? false
        default:
            break
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let api = session.api
                let newTitle = title.trimmingCharacters(in: .whitespaces)
                if newTitle != chat.title { try await api.setChatTitle(chatId: chat.id, title: newTitle) }
                if about != currentDescription { try await api.setChatDescription(chatId: chat.id, description: about) }
                if autoDelete != chat.messageAutoDeleteTime {
                    try await api.setChatMessageAutoDeleteTime(chatId: chat.id, messageAutoDeleteTime: autoDelete)
                }
                if let permissions, permissions != chat.permissions, !chat.isChannel {
                    try await api.setChatPermissions(chatId: chat.id, permissions: permissions)
                }
                if let supergroup, let id = supergroup.supergroup?.id {
                    if username != (supergroup.supergroup?.usernames?.editableUsername ?? "") {
                        try await api.setSupergroupUsername(supergroupId: id, username: username)
                    }
                    if chat.isChannel, signMessages != supergroup.supergroup?.signMessages {
                        try await api.toggleSupergroupSignMessages(showMessageSender: false, signMessages: signMessages, supergroupId: id)
                    }
                    if !chat.isChannel, allHistoryVisible != supergroup.fullInfo?.isAllHistoryAvailable {
                        try await api.toggleSupergroupIsAllHistoryAvailable(isAllHistoryAvailable: allHistoryVisible, supergroupId: id)
                    }
                }
                await session.loadFullInfo(for: chat)
                dismiss()
            } catch {
                errorMessage = error.telegramMessage
                Log.ui.error("Editing chat failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }

    private var currentDescription: String {
        switch chat.type {
        case .chatTypeBasicGroup(let value): session.peers.basicGroup(value.basicGroupId).fullInfo?.description ?? ""
        case .chatTypeSupergroup: supergroup?.fullInfo?.description ?? ""
        default: ""
        }
    }

    private func setPhoto(_ url: URL?) {
        Task {
            do {
                let photo = url.map { InputChatPhoto.inputChatPhotoStatic(InputChatPhotoStatic(photo: .inputFileLocal(InputFileLocal(path: $0.path(percentEncoded: false))))) }
                try await session.api.setChatPhoto(chatId: chat.id, photo: photo)
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }

    private func revokeLink() {
        Task {
            do {
                _ = try await session.api.replacePrimaryChatInviteLink(chatId: chat.id)
                await session.loadFullInfo(for: chat)
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }
}

/// Adds contacts to a group, like tdesktop's `AddParticipantsBoxController`.
struct AddMembersSheet: View {
    let chat: ChatItem
    let onAdded: () -> Void

    @Environment(TelegramSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<Int64> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: String(localized: "Add Members"), errorMessage: errorMessage) {
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
            UserPickerView(selection: $selection)
        }
        .frame(width: 400, height: 520)
    }

    private func add() {
        Task {
            do {
                let failed = try await session.api.addChatMembers(chatId: chat.id, userIds: Array(selection))
                if failed.failedToAddMembers.isEmpty {
                    onAdded()
                    dismiss()
                } else {
                    errorMessage = String(localized: "Some people couldn't be added because of their privacy settings.")
                    onAdded()
                }
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }
}
