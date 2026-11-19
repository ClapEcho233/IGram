//
//  ChatInfoLoading.swift
//  IGram
//

import Foundation
@preconcurrency import TDLibKit

extension TelegramSession {
    /// Fetches the full profile behind a chat: bio, description, members…
    func loadFullInfo(for chat: ChatItem) async {
        switch chat.type {
        case .chatTypePrivate(let value):
            if let info = try? await api.getUserFullInfo(userId: value.userId) {
                peers.store(info, userId: value.userId)
            }
        case .chatTypeSecret(let value):
            if let info = try? await api.getUserFullInfo(userId: value.userId) {
                peers.store(info, userId: value.userId)
            }
        case .chatTypeBasicGroup(let value):
            if let info = try? await api.getBasicGroupFullInfo(basicGroupId: value.basicGroupId) {
                peers.store(info, basicGroupId: value.basicGroupId)
            }
        case .chatTypeSupergroup(let value):
            if let info = try? await api.getSupergroupFullInfo(supergroupId: value.supergroupId) {
                peers.store(info, supergroupId: value.supergroupId)
            }
        }
    }

    /// Recent members of a group, for the info panel.
    func members(of chat: ChatItem, limit: Int = 50) async -> [ChatMember] {
        switch chat.type {
        case .chatTypeBasicGroup(let value):
            return peers.basicGroup(value.basicGroupId).fullInfo?.members ?? []
        case .chatTypeSupergroup(let value) where !value.isChannel:
            guard peers.supergroup(value.supergroupId).fullInfo?.canGetMembers ?? true else { return [] }
            let result = try? await api.getSupergroupMembers(
                filter: .supergroupMembersFilterRecent,
                limit: limit,
                offset: 0,
                supergroupId: value.supergroupId
            )
            return result?.members ?? []
        default:
            return []
        }
    }
}
