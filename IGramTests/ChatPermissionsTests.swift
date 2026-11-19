//
//  ChatPermissionsTests.swift
//  IGramTests
//

import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct ChatPermissionsTests {
    private let all = ChatPermissions(
        canAddLinkPreviews: true, canChangeInfo: true, canCreateTopics: true, canEditTag: true,
        canInviteUsers: true, canPinMessages: true, canReactToMessages: true, canSendAudios: true,
        canSendBasicMessages: true, canSendDocuments: true, canSendOtherMessages: true, canSendPhotos: true,
        canSendPolls: true, canSendVideoNotes: true, canSendVideos: true, canSendVoiceNotes: true
    )

    @Test func changesOnlyTheGivenPermission() {
        let changed = all.with(\.canPinMessages, false)
        #expect(!changed.canPinMessages)
        #expect(changed.canChangeInfo)
        #expect(changed.canSendPhotos)
        #expect(changed.with(\.canPinMessages, true) == all)
    }

    @Test func adminDefaults() {
        let group = TelegramSession.defaultAdminRights(isChannel: false)
        #expect(group.canRestrictMembers && group.canPinMessages && !group.canPostMessages)
        let channel = TelegramSession.defaultAdminRights(isChannel: true)
        #expect(channel.canPostMessages && channel.canEditMessages && !channel.canRestrictMembers)
    }
}
