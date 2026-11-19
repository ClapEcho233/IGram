//
//  HistoryView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// The scrolling message list, after tdesktop's `HistoryInner`.
///
/// Anchored to the bottom, it pages older messages in when the top comes
/// into view and newer ones when a jump left a gap, scrolls to focus requests
/// from the model and offers a jump-to-bottom button.
struct HistoryView: View {
    let chat: ChatItem
    let history: HistoryModel
    /// `lastReadInboxMessageId` captured when the chat was opened.
    let unreadAnchor: Int64?

    @State private var position = ScrollPosition(idType: String.self)
    @State private var isNearBottom = true
    @State private var highlightedMessageId: Int64?

    var body: some View {
        let entries = HistoryLayout.entries(for: history.messages, lastReadInboxMessageId: unreadAnchor)
        ScrollView {
            LazyVStack(spacing: 2) {
                if history.didLoadInitial, history.hasMoreOlder {
                    pagingIndicator
                        .task(id: history.messages.first?.id) { await history.loadOlder() }
                }
                ForEach(entries) { entry in
                    HistoryEntryView(
                        entry: entry,
                        chat: chat,
                        history: history,
                        highlightedMessageId: highlightedMessageId
                    )
                }
                if history.hasMoreNewer {
                    pagingIndicator
                        .task(id: history.messages.last?.id) { await history.loadNewer() }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height - geometry.visibleRect.maxY < 160
        } action: { _, nearBottom in
            isNearBottom = nearBottom
        }
        .onChange(of: history.focusRequest) { _, request in
            guard let request else { return }
            focus(on: request, in: entries)
        }
        .overlay {
            if !history.didLoadInitial {
                ProgressView()
            } else if entries.isEmpty {
                ServiceCapsule(text: String(localized: "No messages here yet…"))
                    .fixedSize()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isNearBottom || history.hasMoreNewer {
                jumpToBottomButton
                    .padding(16)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: isNearBottom)
        .background(ChatTheme.background)
    }

    private var pagingIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(8)
    }

    private var jumpToBottomButton: some View {
        Button {
            Task {
                await history.jumpToLatest()
                if !history.hasMoreNewer {
                    withAnimation { position.scrollTo(edge: .bottom) }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.title3.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: .circle)
                .overlay(alignment: .top) {
                    if chat.unreadCount > 0 {
                        UnreadBadge(count: chat.unreadCount, isMuted: false)
                            .offset(y: -12)
                    }
                }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.downArrow, modifiers: [.command])
        .help("Scroll to the latest message")
    }

    private func focus(on request: HistoryModel.FocusRequest, in entries: [HistoryEntry]) {
        let target = entries.first { entry in
            if case .message(let message) = entry { return message.contains(request.messageId) }
            return false
        }
        guard let target else { return }
        let isLatest = history.messages.last?.id == request.messageId && !history.hasMoreNewer
        Task { @MainActor in
            // Let the lazy stack lay out the new rows first.
            await Task.yield()
            if isLatest && !request.highlight {
                position.scrollTo(edge: .bottom)
            } else {
                withAnimation(.smooth) { position.scrollTo(id: target.id, anchor: .center) }
            }
            if request.highlight {
                highlightedMessageId = request.messageId
                try? await Task.sleep(for: .seconds(1.5))
                if highlightedMessageId == request.messageId { highlightedMessageId = nil }
            }
        }
    }
}
