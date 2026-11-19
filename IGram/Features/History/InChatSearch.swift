//
//  InChatSearch.swift
//  IGram
//

import Observation
import SwiftUI
@preconcurrency import TDLibKit

/// Search inside one chat with result stepping, like tdesktop's
/// `HistoryView::ComposeSearch`.
@Observable
final class InChatSearchModel {
    var isActive = false
    var query = ""
    /// Matching message ids, newest first.
    private(set) var results: [Int64] = []
    private(set) var totalCount = 0
    private(set) var index = 0
    private(set) var isSearching = false

    var current: Int64? { results.indices.contains(index) ? results[index] : nil }

    func search(chatId: Int64, api: TDLibClient) async -> Int64? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            totalCount = 0
            return nil
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return nil }
        isSearching = true
        defer { isSearching = false }
        let found = try? await api.searchChatMessages(
            chatId: chatId, filter: nil, fromMessageId: 0, limit: 100,
            offset: 0, query: trimmed, senderId: nil, topicId: nil
        )
        guard !Task.isCancelled else { return nil }
        results = found?.messages.map(\.id) ?? []
        totalCount = found?.totalCount ?? 0
        index = 0
        return current
    }

    /// Steps to an older (`+1`) or newer (`-1`) result.
    func step(_ delta: Int) -> Int64? {
        guard !results.isEmpty else { return nil }
        index = min(max(index + delta, 0), results.count - 1)
        return current
    }

    func close() {
        isActive = false
        query = ""
        results = []
        totalCount = 0
        index = 0
    }
}

struct InChatSearchBar: View {
    @Bindable var model: InChatSearchModel
    let history: HistoryModel

    @Environment(TelegramSession.self) private var session
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search in this chat", text: $model.query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { jump(model.step(1)) }
                .onExitCommand { model.close() }
            if model.isSearching {
                ProgressView().controlSize(.small)
            } else if !model.query.isEmpty {
                Text(model.results.isEmpty ? String(localized: "No results") : String(localized: "\(model.index + 1) of \(model.totalCount)"))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button { jump(model.step(1)) } label: { Image(systemName: "chevron.up") }
                .disabled(model.index + 1 >= model.results.count)
                .help("Older result")
            Button { jump(model.step(-1)) } label: { Image(systemName: "chevron.down") }
                .disabled(model.index == 0)
                .help("Newer result")
            Button("Done") { model.close() }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { isFocused = true }
        .task(id: model.query) {
            jump(await model.search(chatId: history.chatId, api: session.api))
        }
    }

    private func jump(_ messageId: Int64?) {
        guard let messageId else { return }
        Task { await history.jump(to: messageId) }
    }
}
