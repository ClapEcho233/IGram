//
//  PinnedMessageBar.swift
//  IGram
//

import Foundation
import Observation
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Pinned messages of a chat, like tdesktop's `HistoryView::PinnedTracker`.
/// Clicking the bar jumps to the shown pin and moves on to the previous one.
@Observable
final class PinnedMessagesModel {
    let chatId: Int64
    /// Pinned messages, newest first.
    private(set) var messages: [ChatMessage] = []
    private(set) var index = 0
    private(set) var hiddenUpTo: Int64

    @ObservationIgnored private var observer: UUID?
    @ObservationIgnored private weak var session: TelegramSession?

    init(chatId: Int64) {
        self.chatId = chatId
        hiddenUpTo = Int64(UserDefaults.standard.integer(forKey: Self.hiddenKey(chatId)))
    }

    var current: ChatMessage? { messages.indices.contains(index) ? messages[index] : nil }
    var isVisible: Bool { (messages.first?.id ?? 0) > hiddenUpTo }

    func attach(to session: TelegramSession) async {
        self.session = session
        if observer == nil {
            observer = session.addObserver { [weak self] update in
                guard let self else { return }
                switch update {
                case .updateMessageIsPinned(let value) where value.chatId == self.chatId:
                    Task { await self.reload() }
                case .updateDeleteMessages(let value) where value.chatId == self.chatId && !value.fromCache:
                    self.messages.removeAll { value.messageIds.contains($0.id) }
                    self.index = min(self.index, max(self.messages.count - 1, 0))
                default:
                    break
                }
            }
        }
        await reload()
    }

    func detach() {
        if let observer { session?.removeObserver(observer) }
        observer = nil
    }

    func reload() async {
        guard let session else { return }
        do {
            let found = try await session.api.searchChatMessages(
                chatId: chatId, filter: .searchMessagesFilterPinned, fromMessageId: 0,
                limit: 100, offset: 0, query: "", senderId: nil, topicId: nil
            )
            messages = found.messages.map(ChatMessage.init)
            index = 0
        } catch {
            Log.data.error("Pinned messages failed: \(error.telegramMessage, privacy: .public)")
        }
    }

    /// Returns the message to jump to and advances to the next older pin.
    func advance() -> ChatMessage? {
        guard let current else { return nil }
        index = messages.isEmpty ? 0 : (index + 1) % messages.count
        return current
    }

    /// Hides the bar until a newer message is pinned.
    func hide() {
        hiddenUpTo = messages.first?.id ?? 0
        UserDefaults.standard.set(Int(hiddenUpTo), forKey: Self.hiddenKey(chatId))
    }

    private static func hiddenKey(_ chatId: Int64) -> String { "pinned.hiddenUpTo.\(chatId)" }
}

struct PinnedMessageBar: View {
    let model: PinnedMessagesModel
    let history: HistoryModel

    @Environment(TelegramSession.self) private var session
    @State private var isConfirmingUnpinAll = false

    var body: some View {
        if model.isVisible, let message = model.current {
            HStack(spacing: 10) {
                PinIndexIndicator(count: model.messages.count, index: model.index)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.messages.count > 1 && model.index > 0
                         ? String(localized: "Pinned Message #\(model.messages.count - model.index)")
                         : String(localized: "Pinned Message"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(message.isService ? session.formatter().serviceText(for: message) : session.formatter().preview(message.content))
                        .font(.callout)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    model.hide()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Hide pinned message")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .contentShape(.rect)
            .onTapGesture {
                if let target = model.advance() {
                    Task { await history.jump(to: target.id) }
                }
            }
            .contextMenu {
                Button("Unpin", systemImage: "pin.slash") {
                    Task { try? await session.api.unpinChatMessage(chatId: model.chatId, messageId: message.id) }
                }
                if model.messages.count > 1 {
                    Button("Unpin All Messages", systemImage: "pin.slash", role: .destructive) { isConfirmingUnpinAll = true }
                }
            }
            .confirmationDialog("Unpin all \(model.messages.count) messages?", isPresented: $isConfirmingUnpinAll) {
                Button("Unpin All", role: .destructive) {
                    Task { try? await session.api.unpinAllChatMessages(chatId: model.chatId) }
                }
            }
        }
    }
}

/// tdesktop's segmented line showing which pin is displayed.
private struct PinIndexIndicator: View {
    let count: Int
    let index: Int

    var body: some View {
        let segments = min(count, 4)
        VStack(spacing: 2) {
            ForEach(0..<max(segments, 1), id: \.self) { segment in
                RoundedRectangle(cornerRadius: 1)
                    .fill(segment == min(index, segments - 1) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.3)))
            }
        }
        .frame(width: 3, height: 32)
    }
}
