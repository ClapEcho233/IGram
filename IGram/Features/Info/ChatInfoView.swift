//
//  ChatInfoView.swift
//  IGram
//

import AppKit
import SwiftUI
@preconcurrency import TDLibKit

/// The profile panel shown in the inspector, after tdesktop's `Info::Profile`.
struct ChatInfoView: View {
    let chat: ChatItem

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @State private var members: [ChatMember] = []
    @State private var mediaKind: SharedMediaModel.Kind = .media
    @State private var pendingRemoval: ChatRemoval?
    @State private var isEditing = false
    @State private var isAddingMembers = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                details
                notificationToggle
                if !members.isEmpty { membersSection }
                SharedMediaSection(chat: chat, kind: $mediaKind)
                actions
            }
            .padding(16)
        }
        .task(id: chat.id) {
            await session.loadFullInfo(for: chat)
            members = await session.members(of: chat)
        }
        .chatRemovalConfirmation($pendingRemoval, session: session)
        .toolbar {
            if session.canEditInfo(chat) {
                ToolbarItem {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditChatSheet(chat: chat)
        }
        .sheet(isPresented: $isAddingMembers) {
            AddMembersSheet(chat: chat) {
                Task {
                    await session.loadFullInfo(for: chat)
                    members = await session.members(of: chat)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            ProfilePhoto(chat: chat)
                .frame(width: 96, height: 96)
            Text(session.title(of: chat))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Text(session.subtitle(for: chat))
                .font(.callout)
                .foregroundStyle(session.isOnline(chat) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Details

    @ViewBuilder
    private var details: some View {
        let rows = detailRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.label) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.value)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(row.value, forType: .string)
                        }
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
    }

    private struct DetailRow {
        let label: String
        let value: String
    }

    private var detailRows: [DetailRow] {
        var rows: [DetailRow] = []
        if let userId = chat.userId {
            let item = session.peers.user(userId)
            if let phone = item.user?.phoneNumber, !phone.isEmpty {
                rows.append(DetailRow(label: String(localized: "Mobile"), value: "+\(phone)"))
            }
            if let username = item.user?.username {
                rows.append(DetailRow(label: String(localized: "Username"), value: "@\(username)"))
            }
            if let bio = item.fullInfo?.bio?.text, !bio.isEmpty {
                rows.append(DetailRow(label: item.user?.isBot == true ? String(localized: "About") : String(localized: "Bio"), value: bio))
            } else if let about = item.fullInfo?.botInfo?.shortDescription, !about.isEmpty {
                rows.append(DetailRow(label: String(localized: "About"), value: about))
            }
        }
        switch chat.type {
        case .chatTypeBasicGroup(let value):
            if let description = session.peers.basicGroup(value.basicGroupId).fullInfo?.description, !description.isEmpty {
                rows.append(DetailRow(label: String(localized: "Description"), value: description))
            }
            if let link = session.peers.basicGroup(value.basicGroupId).fullInfo?.inviteLink?.inviteLink {
                rows.append(DetailRow(label: String(localized: "Invite Link"), value: link))
            }
        case .chatTypeSupergroup(let value):
            let item = session.peers.supergroup(value.supergroupId)
            if let description = item.fullInfo?.description, !description.isEmpty {
                rows.append(DetailRow(label: String(localized: "Description"), value: description))
            }
            if let username = item.supergroup?.usernames?.activeUsernames.first {
                rows.append(DetailRow(label: String(localized: "Link"), value: "https://t.me/\(username)"))
            } else if let link = item.fullInfo?.inviteLink?.inviteLink {
                rows.append(DetailRow(label: String(localized: "Invite Link"), value: link))
            }
        default:
            break
        }
        return rows
    }

    @ViewBuilder
    private var notificationToggle: some View {
        if !session.isSavedMessages(chat) {
            Toggle(isOn: Binding(
                get: { !session.chats.isMuted(chat) },
                set: { enabled in Task { try? await session.setMuted(chat, muted: !enabled) } }
            )) {
                Label("Notifications", systemImage: "bell")
            }
            .toggleStyle(.switch)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        }
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Members")
                    .font(.headline)
                Spacer()
                if session.canInviteMembers(chat) {
                    Button("Add", systemImage: "person.badge.plus") { isAddingMembers = true }
                        .buttonStyle(.borderless)
                }
            }
            ForEach(members, id: \.memberId) { member in
                Button {
                    if let userId = member.memberId.userId, userId != session.myUserId {
                        Task {
                            if let chat = try? await session.api.createPrivateChat(force: false, userId: userId) {
                                main.open(chatId: chat.id)
                            }
                        }
                    }
                } label: {
                    MemberRow(member: member)
                }
                .buttonStyle(.plain)
                .contextMenu { memberMenu(member) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func memberMenu(_ member: ChatMember) -> some View {
        if member.memberId.userId != session.myUserId {
            switch member.status {
            case .chatMemberStatusCreator:
                EmptyView()
            case .chatMemberStatusAdministrator:
                if session.canPromoteMembers(chat) {
                    Button("Dismiss Admin", systemImage: "person.badge.minus") { runMemberAction { try await session.dismissAdmin(member.memberId, in: chat) } }
                }
            default:
                if session.canPromoteMembers(chat) {
                    Button("Make Admin", systemImage: "star") { runMemberAction { try await session.promote(member.memberId, in: chat) } }
                }
            }
            if session.canRestrictMembers(chat), !isCreatorStatus(member.status) {
                Button(chat.isChannel ? "Remove from Channel" : "Remove from Group", systemImage: "person.fill.xmark", role: .destructive) {
                    runMemberAction { try await session.removeMember(member.memberId, from: chat) }
                }
            }
        }
    }

    private func isCreatorStatus(_ status: ChatMemberStatus) -> Bool {
        if case .chatMemberStatusCreator = status { return true }
        return false
    }

    private func runMemberAction(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                main.showToast(error.telegramMessage)
            }
            await session.loadFullInfo(for: chat)
            members = await session.members(of: chat)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 8) {
            if let userId = chat.userId, userId != session.myUserId {
                let sender = MessageSender.messageSenderUser(MessageSenderUser(userId: userId))
                Button(chat.blockList == nil ? "Block User" : "Unblock User", role: chat.blockList == nil ? .destructive : nil) {
                    let list: BlockList? = chat.blockList == nil ? .blockListMain : nil
                    Task { try? await session.api.setMessageSenderBlockList(blockList: list, senderId: sender) }
                }
            }
            if session.canLeave(chat) {
                Button(chat.isChannel ? "Leave Channel" : "Leave Group", role: .destructive) {
                    pendingRemoval = ChatRemoval(chat: chat, kind: .leave)
                }
            } else if !session.isSavedMessages(chat) {
                Button("Delete Chat", role: .destructive) {
                    pendingRemoval = ChatRemoval(chat: chat, kind: .delete)
                }
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The chat photo at full size, falling back to the avatar.
private struct ProfilePhoto: View {
    let chat: ChatItem

    @Environment(TelegramSession.self) private var session

    var body: some View {
        if let photo = chat.photo, !session.isSavedMessages(chat) {
            FileImage(file: photo.big, maxPixelSize: 400, priority: .media) {
                AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 96)
            }
            .clipShape(.circle)
        } else {
            AvatarView(content: .chat(chat, myUserId: session.myUserId), size: 96)
        }
    }
}

private struct MemberRow: View {
    let member: ChatMember

    @Environment(TelegramSession.self) private var session

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(content: session.avatar(of: member.memberId), size: 32, isOnline: isOnline)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayName(member.memberId)).lineLimit(1)
                if let userId = member.memberId.userId {
                    Text(DateFormatting().presence(session.peers.user(userId).status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let role {
                Text(role).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }

    private var isOnline: Bool {
        member.memberId.userId.map { DateFormatting.isOnline(session.peers.user($0).status) } ?? false
    }

    private var role: String? {
        switch member.status {
        case .chatMemberStatusCreator: String(localized: "owner")
        case .chatMemberStatusAdministrator: member.tag.isEmpty ? String(localized: "admin") : member.tag
        default: member.tag.isEmpty ? nil : member.tag
        }
    }
}
