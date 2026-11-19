//
//  ChatSearchModel.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// Global search from the chat list, like tdesktop's `Dialogs::InnerWidget`
/// search mode: known chats, public chats and messages.
@Observable
final class ChatSearchModel {
    private(set) var chatIds: [Int64] = []
    private(set) var publicChatIds: [Int64] = []
    private(set) var messages: [Message] = []
    private(set) var isSearching = false
    @ObservationIgnored private var nextOffset = ""
    @ObservationIgnored private var query = ""

    func search(_ text: String, api: TDLibClient) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed
        guard !trimmed.isEmpty else {
            chatIds = []
            publicChatIds = []
            messages = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, query == trimmed else { return }
        isSearching = true
        defer { isSearching = false }

        async let local = try? api.searchChats(limit: 30, query: trimmed, typeFilter: nil)
        async let server = try? api.searchChatsOnServer(limit: 30, query: trimmed, typeFilter: nil)
        async let found = try? api.searchMessages(
            chatList: nil, chatTypeFilter: nil, filter: nil, limit: 40,
            maxDate: 0, minDate: 0, offset: "", query: trimmed
        )
        let isPublicQuery = trimmed.count >= 4 && !trimmed.hasPrefix("#")
        let publicChats = isPublicQuery ? try? await api.searchPublicChats(query: trimmed, typeFilter: nil) : nil

        let localIds = await local?.chatIds ?? []
        let serverIds = await server?.chatIds ?? []
        let foundMessages = await found
        guard query == trimmed else { return }

        var seen = Set<Int64>()
        chatIds = (localIds + serverIds).filter { seen.insert($0).inserted }
        publicChatIds = (publicChats?.chatIds ?? []).filter { seen.insert($0).inserted }
        messages = foundMessages?.messages ?? []
        nextOffset = foundMessages?.nextOffset ?? ""
    }

    func loadMoreMessages(api: TDLibClient) async {
        guard !nextOffset.isEmpty, !isSearching else { return }
        let offset = nextOffset
        nextOffset = ""
        let current = query
        guard let found = try? await api.searchMessages(
            chatList: nil, chatTypeFilter: nil, filter: nil, limit: 40,
            maxDate: 0, minDate: 0, offset: offset, query: current
        ), current == query else { return }
        messages += found.messages
        nextOffset = found.nextOffset
    }
}
