//
//  SharedMediaModel.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// Shared media of a chat for one filter, like tdesktop's `Info::Media` lists.
@Observable
final class SharedMediaModel {
    enum Kind: String, CaseIterable, Identifiable {
        case media, files, links, voice

        var id: String { rawValue }

        var title: String {
            switch self {
            case .media: String(localized: "Media")
            case .files: String(localized: "Files")
            case .links: String(localized: "Links")
            case .voice: String(localized: "Voice")
            }
        }

        var filter: SearchMessagesFilter {
            switch self {
            case .media: .searchMessagesFilterPhotoAndVideo
            case .files: .searchMessagesFilterDocument
            case .links: .searchMessagesFilterUrl
            case .voice: .searchMessagesFilterVoiceNote
            }
        }
    }

    let chatId: Int64
    let kind: Kind
    private(set) var messages: [ChatMessage] = []
    private(set) var isLoading = false
    private(set) var isComplete = false
    @ObservationIgnored private var nextFromMessageId: Int64 = 0
    @ObservationIgnored private let api: TDLibClient

    init(chatId: Int64, kind: Kind, api: TDLibClient) {
        self.chatId = chatId
        self.kind = kind
        self.api = api
    }

    func loadMore() async {
        guard !isLoading, !isComplete else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await api.searchChatMessages(
                chatId: chatId,
                filter: kind.filter,
                fromMessageId: nextFromMessageId,
                limit: 60,
                offset: 0,
                query: "",
                senderId: nil,
                topicId: nil
            )
            messages += found.messages.map(ChatMessage.init)
            nextFromMessageId = found.nextFromMessageId
            isComplete = found.nextFromMessageId == 0 || found.messages.isEmpty
        } catch {
            Log.data.error("Shared media failed: \(error.telegramMessage, privacy: .public)")
            isComplete = true
        }
    }
}
