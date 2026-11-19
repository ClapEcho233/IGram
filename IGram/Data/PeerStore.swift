//
//  PeerStore.swift
//  IGram
//

import Foundation
import Observation
@preconcurrency import TDLibKit

/// Observable wrapper for one user so views only refresh when that user changes.
@Observable
final class UserItem: Identifiable {
    let id: Int64
    private(set) var user: User?
    /// Tracked separately because `updateUserStatus` arrives far more often than `updateUser`.
    private(set) var status: UserStatus = .userStatusEmpty
    private(set) var fullInfo: UserFullInfo?

    init(id: Int64) { self.id = id }

    fileprivate func apply(_ user: User) {
        self.user = user
        status = user.status
    }

    fileprivate func apply(status: UserStatus) { self.status = status }
    fileprivate func apply(fullInfo: UserFullInfo) { self.fullInfo = fullInfo }

    var fullName: String { user?.fullName ?? "" }
}

@Observable
final class BasicGroupItem: Identifiable {
    let id: Int64
    private(set) var group: BasicGroup?
    private(set) var fullInfo: BasicGroupFullInfo?

    init(id: Int64) { self.id = id }

    fileprivate func apply(_ group: BasicGroup) { self.group = group }
    fileprivate func apply(fullInfo: BasicGroupFullInfo) { self.fullInfo = fullInfo }
}

@Observable
final class SupergroupItem: Identifiable {
    let id: Int64
    private(set) var supergroup: Supergroup?
    private(set) var fullInfo: SupergroupFullInfo?

    init(id: Int64) { self.id = id }

    fileprivate func apply(_ supergroup: Supergroup) { self.supergroup = supergroup }
    fileprivate func apply(fullInfo: SupergroupFullInfo) { self.fullInfo = fullInfo }
}

/// Users, basic groups, supergroups and secret chats known to the session.
///
/// Equivalent to the peer caches in tdesktop's `Data::Session`. Lookups never
/// fail: an unknown id yields an empty item that fills in once TDLib sends it.
final class PeerStore {
    private var users: [Int64: UserItem] = [:]
    private var basicGroups: [Int64: BasicGroupItem] = [:]
    private var supergroups: [Int64: SupergroupItem] = [:]
    private var secretChats: [Int: SecretChat] = [:]

    func user(_ id: Int64) -> UserItem {
        if let item = users[id] { return item }
        let item = UserItem(id: id)
        users[id] = item
        return item
    }

    func basicGroup(_ id: Int64) -> BasicGroupItem {
        if let item = basicGroups[id] { return item }
        let item = BasicGroupItem(id: id)
        basicGroups[id] = item
        return item
    }

    func supergroup(_ id: Int64) -> SupergroupItem {
        if let item = supergroups[id] { return item }
        let item = SupergroupItem(id: id)
        supergroups[id] = item
        return item
    }

    func secretChat(_ id: Int) -> SecretChat? { secretChats[id] }

    /// Applies peer-related updates. Returns `true` when the update was consumed.
    @discardableResult
    func handle(_ update: Update) -> Bool {
        switch update {
        case .updateUser(let value):
            user(value.user.id).apply(value.user)
        case .updateUserStatus(let value):
            user(value.userId).apply(status: value.status)
        case .updateUserFullInfo(let value):
            user(value.userId).apply(fullInfo: value.userFullInfo)
        case .updateBasicGroup(let value):
            basicGroup(value.basicGroup.id).apply(value.basicGroup)
        case .updateBasicGroupFullInfo(let value):
            basicGroup(value.basicGroupId).apply(fullInfo: value.basicGroupFullInfo)
        case .updateSupergroup(let value):
            supergroup(value.supergroup.id).apply(value.supergroup)
        case .updateSupergroupFullInfo(let value):
            supergroup(value.supergroupId).apply(fullInfo: value.supergroupFullInfo)
        case .updateSecretChat(let value):
            secretChats[value.secretChat.id] = value.secretChat
        default:
            return false
        }
        return true
    }
}

extension User {
    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var isDeleted: Bool {
        if case .userTypeDeleted = type { return true }
        return false
    }

    var isBot: Bool {
        if case .userTypeBot = type { return true }
        return false
    }

    /// The primary public username, if any.
    var username: String? { usernames?.activeUsernames.first }
}
