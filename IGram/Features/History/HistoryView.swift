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

    @Environment(TelegramSession.self) private var session: TelegramSession?
    @Environment(\.colorScheme) private var colorScheme
    @State private var position = ScrollPosition(idType: String.self)
    @State private var scrollActivity = HistoryScrollActivity()
    @State private var isNearBottom = true
    @State private var highlightedMessageId: Int64?

    var body: some View {
        let entries = history.entries(lastReadInboxMessageId: unreadAnchor)
        ScrollView {
            LazyVStack(spacing: 0) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .onScrollPhaseChange { _, phase in
            scrollActivity.update(isScrolling: phase != .idle)
        }
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.2) { ids in
            // Rows ascend by date, so the earliest visible day is the top one.
            let day = ids.compactMap { history.day(ofRow: $0) }.min()
            if day != scrollActivity.topDay { scrollActivity.topDay = day }
        }
        .overlay(alignment: .top) {
            FloatingDayHeader(activity: scrollActivity)
        }
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
            VStack(spacing: 12) {
                if chat.unreadReactionCount > 0 {
                    UnreadJumpButton(systemImage: "heart", count: chat.unreadReactionCount, help: "Next unread reaction") {
                        await jumpToFirst(.searchMessagesFilterUnreadReaction)
                    }
                }
                if chat.unreadMentionCount > 0 {
                    UnreadJumpButton(systemImage: "at", count: chat.unreadMentionCount, help: "Next unread mention") {
                        await jumpToFirst(.searchMessagesFilterUnreadMention)
                    }
                }
                if !isNearBottom || history.hasMoreNewer {
                    jumpToBottomButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)
        }
        .animation(.snappy, value: isNearBottom)
        .environment(\.chatThemeStyle, resolvedThemeStyle)
        .background { ChatBackgroundView(chat: chat) }
    }

    private var resolvedThemeStyle: ChatThemeStyle {
        let isDark = colorScheme == .dark
        let preset = DisplayPreferences.shared.chatPreset
        let settings = session?.themes.themeSettings(for: chat, isDark: isDark)
        return ChatThemeStyle(preset: preset, settings: settings, isDark: isDark)
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
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.interactive(), in: .circle)
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

    /// Jumps to the oldest unread mention or reaction, as tdesktop's corner buttons do.
    private func jumpToFirst(_ filter: SearchMessagesFilter) async {
        guard let api = session?.api,
              let found = try? await api.searchChatMessages(
                  chatId: chat.id, filter: filter, fromMessageId: 0, limit: 100,
                  offset: 0, query: "", senderId: nil, topicId: nil
              ),
              let oldest = found.messages.last
        else { return }
        await history.jump(to: oldest.id)
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

/// The day of the topmost visible message and whether the history is being
/// scrolled, for the floating date pill. Only the pill reads it, so a scroll
/// doesn't re-render the whole history.
///
/// SwiftUI's pinned section headers would do this for free, but in a
/// bottom-anchored lazy stack they left long chats blank and made the history
/// jump when the window became active.
@Observable
final class HistoryScrollActivity {
    private(set) var isScrolling = false
    var topDay: Date?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// Shows the pill at once and keeps it a moment after scrolling stops,
    /// like Telegram's floating date.
    func update(isScrolling scrolling: Bool) {
        hideTask?.cancel()
        if scrolling {
            if !isScrolling { isScrolling = true }
            return
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.isScrolling = false
        }
    }
}

/// The date of the messages at the top, floating while the history scrolls.
private struct FloatingDayHeader: View {
    let activity: HistoryScrollActivity

    var body: some View {
        ZStack {
            if activity.isScrolling, let day = activity.topDay {
                DayHeader(date: day)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: activity.isScrolling)
    }
}

/// A round corner button with a counter, used for unread mentions and reactions.
private struct UnreadJumpButton: View {
    let systemImage: String
    let count: Int
    let help: LocalizedStringKey
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.interactive(), in: .circle)
                .overlay(alignment: .top) {
                    UnreadBadge(count: count).offset(y: -12)
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
