//
//  ChatAdministration.swift
//  IGram
//

import Foundation
@preconcurrency import TDLibKit

/// The current user's rights in groups and channels, after tdesktop's
/// `PeerData::canEditInformation` and friends.
extension TelegramSession {
    func memberStatus(in chat: ChatItem) -> ChatMemberStatus? {
        switch chat.type {
        case .chatTypeBasicGroup(let value): peers.basicGroup(value.basicGroupId).group?.status
        case .chatTypeSupergroup(let value): peers.supergroup(value.supergroupId).supergroup?.status
        default: nil
        }
    }

    /// Admin rights of the current user, or `nil` if they aren't an admin.
    func adminRights(in chat: ChatItem) -> ChatAdministratorRights? {
        switch memberStatus(in: chat) {
        case .chatMemberStatusCreator: Self.allRights
        case .chatMemberStatusAdministrator(let admin): admin.rights
        default: nil
        }
    }

    func canEditInfo(_ chat: ChatItem) -> Bool {
        if let rights = adminRights(in: chat) { return rights.canChangeInfo }
        if case .chatTypeBasicGroup = chat.type { return chat.permissions.canChangeInfo }
        return false
    }

    func canInviteMembers(_ chat: ChatItem) -> Bool {
        if let rights = adminRights(in: chat) { return rights.canInviteUsers }
        return !chat.isChannel && chat.permissions.canInviteUsers
    }

    func canRestrictMembers(_ chat: ChatItem) -> Bool {
        adminRights(in: chat)?.canRestrictMembers ?? false
    }

    func canPromoteMembers(_ chat: ChatItem) -> Bool {
        adminRights(in: chat)?.canPromoteMembers ?? false
    }

    func isCreator(of chat: ChatItem) -> Bool {
        if case .chatMemberStatusCreator = memberStatus(in: chat) { return true }
        return false
    }

    /// Rights granted when promoting someone to admin, matching tdesktop's defaults.
    static func defaultAdminRights(isChannel: Bool) -> ChatAdministratorRights {
        ChatAdministratorRights(
            canChangeInfo: true,
            canDeleteMessages: true,
            canDeleteStories: isChannel,
            canEditMessages: isChannel,
            canEditStories: isChannel,
            canInviteUsers: true,
            canManageChat: true,
            canManageDirectMessages: false,
            canManageTags: !isChannel,
            canManageTopics: !isChannel,
            canManageVideoChats: true,
            canPinMessages: !isChannel,
            canPostMessages: isChannel,
            canPostStories: isChannel,
            canPromoteMembers: false,
            canRestrictMembers: !isChannel,
            canSendWelcomeMessages: false,
            isAnonymous: false
        )
    }

    static let allRights = ChatAdministratorRights(
        canChangeInfo: true, canDeleteMessages: true, canDeleteStories: true, canEditMessages: true,
        canEditStories: true, canInviteUsers: true, canManageChat: true, canManageDirectMessages: true,
        canManageTags: true, canManageTopics: true, canManageVideoChats: true, canPinMessages: true,
        canPostMessages: true, canPostStories: true, canPromoteMembers: true, canRestrictMembers: true,
        canSendWelcomeMessages: true, isAnonymous: false
    )

    func promote(_ member: MessageSender, in chat: ChatItem) async throws {
        try await api.setChatMemberStatus(
            chatId: chat.id,
            memberId: member,
            status: .chatMemberStatusAdministrator(ChatMemberStatusAdministrator(
                canBeEdited: true,
                rights: Self.defaultAdminRights(isChannel: chat.isChannel)
            ))
        )
    }

    func dismissAdmin(_ member: MessageSender, in chat: ChatItem) async throws {
        try await api.setChatMemberStatus(
            chatId: chat.id,
            memberId: member,
            status: .chatMemberStatusMember(ChatMemberStatusMember(memberUntilDate: 0))
        )
    }

    func removeMember(_ member: MessageSender, from chat: ChatItem) async throws {
        try await api.banChatMember(bannedUntilDate: 0, chatId: chat.id, memberId: member, revokeMessages: false)
    }
}

extension ChatPermissions {
    /// A copy with one permission changed; TDLib's model is immutable.
    func with(_ keyPath: KeyPath<ChatPermissions, Bool>, _ value: Bool) -> ChatPermissions {
        func pick(_ path: KeyPath<ChatPermissions, Bool>) -> Bool { path == keyPath ? value : self[keyPath: path] }
        return ChatPermissions(
            canAddLinkPreviews: pick(\.canAddLinkPreviews),
            canChangeInfo: pick(\.canChangeInfo),
            canCreateTopics: pick(\.canCreateTopics),
            canEditTag: pick(\.canEditTag),
            canInviteUsers: pick(\.canInviteUsers),
            canPinMessages: pick(\.canPinMessages),
            canReactToMessages: pick(\.canReactToMessages),
            canSendAudios: pick(\.canSendAudios),
            canSendBasicMessages: pick(\.canSendBasicMessages),
            canSendDocuments: pick(\.canSendDocuments),
            canSendOtherMessages: pick(\.canSendOtherMessages),
            canSendPhotos: pick(\.canSendPhotos),
            canSendPolls: pick(\.canSendPolls),
            canSendVideoNotes: pick(\.canSendVideoNotes),
            canSendVideos: pick(\.canSendVideos),
            canSendVoiceNotes: pick(\.canSendVoiceNotes)
        )
    }
}
