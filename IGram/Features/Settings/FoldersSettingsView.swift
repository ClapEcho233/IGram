//
//  FoldersSettingsView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Chat folder management, after tdesktop's `Settings::Folders`.
struct FoldersSettingsView: View {
    @Environment(TelegramSession.self) private var session
    @State private var recommended: [RecommendedChatFolder] = []
    @State private var editing: FolderDraft?
    @State private var pendingDeletion: ChatFolderInfo?

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(session.folders.folders, id: \.id) { folder in
                        HStack {
                            Image(systemName: ChatFolderTab.folder(folder).systemImage)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            Text(folder.name.text.text)
                            Spacer()
                            Button("Edit") { edit(folder) }
                                .buttonStyle(.link)
                            Button {
                                pendingDeletion = folder
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete folder")
                        }
                    }
                    .onMove(perform: move)
                }
                .frame(minHeight: CGFloat(max(session.folders.folders.count, 1)) * 30)
                Button("Create New Folder…", systemImage: "folder.badge.plus") {
                    editing = FolderDraft()
                }
            } header: {
                Text("My Folders")
            } footer: {
                Text("Drag folders to reorder them.").foregroundStyle(.secondary)
            }
            if !recommended.isEmpty {
                Section("Recommended Folders") {
                    ForEach(Array(recommended.enumerated()), id: \.offset) { _, item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.folder.name.text.text)
                                Text(item.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") { add(item.folder) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await loadRecommended() }
        .sheet(item: $editing) { draft in
            FolderEditorSheet(draft: draft)
        }
        .confirmationDialog("Delete this folder?", item: $pendingDeletion) { folder in
            Button("Delete “\(folder.name.text.text)”", role: .destructive) {
                Task { try? await session.api.deleteChatFolder(chatFolderId: folder.id, leaveChatIds: []) }
            }
        } message: { _ in
            Text("The chats in it stay in your chat list.")
        }
    }

    private func edit(_ info: ChatFolderInfo) {
        Task {
            if let folder = try? await session.api.getChatFolder(chatFolderId: info.id) {
                editing = FolderDraft(id: info.id, folder: folder)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = session.folders.folders.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        let position = session.folders.mainChatListPosition
        Task { try? await session.api.reorderChatFolders(chatFolderIds: ids, mainChatListPosition: position) }
    }

    private func add(_ folder: ChatFolder) {
        Task {
            _ = try? await session.api.createChatFolder(folder: folder)
            await loadRecommended()
        }
    }

    private func loadRecommended() async {
        recommended = (try? await session.api.getRecommendedChatFolders())?.chatFolders ?? []
    }
}

/// An editable copy of a chat folder.
struct FolderDraft: Identifiable {
    let id: Int?
    var name = ""
    var includeContacts = false
    var includeNonContacts = false
    var includeGroups = false
    var includeChannels = false
    var includeBots = false
    var excludeMuted = false
    var excludeRead = false
    var excludeArchived = false
    var includedChatIds: [Int64] = []
    var excludedChatIds: [Int64] = []
    var pinnedChatIds: [Int64] = []
    var icon: ChatFolderIcon?
    var colorId = -1

    init() { id = nil }

    init(id: Int, folder: ChatFolder) {
        self.id = id
        name = folder.name.text.text
        includeContacts = folder.includeContacts
        includeNonContacts = folder.includeNonContacts
        includeGroups = folder.includeGroups
        includeChannels = folder.includeChannels
        includeBots = folder.includeBots
        excludeMuted = folder.excludeMuted
        excludeRead = folder.excludeRead
        excludeArchived = folder.excludeArchived
        includedChatIds = folder.includedChatIds
        excludedChatIds = folder.excludedChatIds
        pinnedChatIds = folder.pinnedChatIds
        icon = folder.icon
        colorId = folder.colorId
    }

    var isEmpty: Bool {
        !(includeContacts || includeNonContacts || includeGroups || includeChannels || includeBots) && includedChatIds.isEmpty
    }

    var folder: ChatFolder {
        ChatFolder(
            colorId: colorId,
            excludeArchived: excludeArchived,
            excludeMuted: excludeMuted,
            excludeRead: excludeRead,
            excludedChatIds: excludedChatIds,
            icon: icon,
            includeBots: includeBots,
            includeChannels: includeChannels,
            includeContacts: includeContacts,
            includeGroups: includeGroups,
            includeNonContacts: includeNonContacts,
            includedChatIds: includedChatIds,
            isShareable: false,
            name: ChatFolderName(animateCustomEmoji: false, text: FormattedText(entities: [], text: name)),
            pinnedChatIds: pinnedChatIds.filter(includedChatIds.contains)
        )
    }
}

/// Creates or edits a folder, after tdesktop's `EditFilterBox`.
struct FolderEditorSheet: View {
    @State var draft: FolderDraft

    @Environment(TelegramSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var pickingFor: Picking?
    @State private var errorMessage: String?

    private enum Picking: String, Identifiable {
        case include, exclude
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: draft.id == nil ? String(localized: "New Folder") : String(localized: "Edit Folder"), errorMessage: errorMessage) {
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.isEmpty)
            }
            Form {
                TextField("Folder name", text: $draft.name)
                Section("Included Chats") {
                    Toggle("Contacts", isOn: $draft.includeContacts)
                    Toggle("Non-Contacts", isOn: $draft.includeNonContacts)
                    Toggle("Groups", isOn: $draft.includeGroups)
                    Toggle("Channels", isOn: $draft.includeChannels)
                    Toggle("Bots", isOn: $draft.includeBots)
                    chatList($draft.includedChatIds)
                    Button("Add Chats…", systemImage: "plus") { pickingFor = .include }
                }
                Section("Excluded Chats") {
                    Toggle("Muted", isOn: $draft.excludeMuted)
                    Toggle("Read", isOn: $draft.excludeRead)
                    Toggle("Archived", isOn: $draft.excludeArchived)
                    chatList($draft.excludedChatIds)
                    Button("Add Chats…", systemImage: "plus") { pickingFor = .exclude }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 440, height: 600)
        .sheet(item: $pickingFor) { target in
            VStack(spacing: 0) {
                SheetHeader(title: target == .include ? String(localized: "Include Chat") : String(localized: "Exclude Chat"))
                ChatPickerView(includesReadOnlyChats: true) { chat in
                    switch target {
                    case .include:
                        if !draft.includedChatIds.contains(chat.id) { draft.includedChatIds.append(chat.id) }
                        draft.excludedChatIds.removeAll { $0 == chat.id }
                    case .exclude:
                        if !draft.excludedChatIds.contains(chat.id) { draft.excludedChatIds.append(chat.id) }
                        draft.includedChatIds.removeAll { $0 == chat.id }
                    }
                    pickingFor = nil
                }
            }
            .frame(width: 380, height: 480)
        }
    }

    private func chatList(_ ids: Binding<[Int64]>) -> some View {
        ForEach(ids.wrappedValue, id: \.self) { chatId in
            HStack {
                if let chat = session.chats.chat(chatId) {
                    AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 24)
                    Text(session.title(of: chat)).lineLimit(1)
                } else {
                    Text("Chat \(chatId)")
                }
                Spacer()
                Button {
                    ids.wrappedValue.removeAll { $0 == chatId }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func save() {
        Task {
            do {
                if let id = draft.id {
                    _ = try await session.api.editChatFolder(chatFolderId: id, folder: draft.folder)
                } else {
                    _ = try await session.api.createChatFolder(folder: draft.folder)
                }
                dismiss()
            } catch {
                errorMessage = error.telegramMessage
                Log.ui.error("Saving folder failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }
}
