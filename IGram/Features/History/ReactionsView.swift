//
//  ReactionsView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Reaction chips under a message, after tdesktop's `HistoryView::Reactions::InlineList`.
struct ReactionsView: View {
    let message: ChatMessage
    let reactions: [MessageReaction]
    let isOutgoingStyle: Bool

    @Environment(TelegramSession.self) private var session

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(reactions, id: \.type) { reaction in
                Button {
                    ReactionActions.toggle(reaction.type, isChosen: reaction.isChosen, on: message, session: session)
                } label: {
                    HStack(spacing: 3) {
                        Text(ReactionActions.symbol(for: reaction.type))
                        Text(reaction.totalCount.formatted(.number.notation(.compactName)))
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .foregroundStyle(reaction.isChosen ? AnyShapeStyle(.white) : AnyShapeStyle(ChatTheme.accent(outgoing: isOutgoingStyle)))
                    .background(
                        reaction.isChosen
                            ? AnyShapeStyle(ChatTheme.accent(outgoing: isOutgoingStyle))
                            : AnyShapeStyle(ChatTheme.accent(outgoing: isOutgoingStyle).opacity(0.14)),
                        in: .capsule
                    )
                }
                .buttonStyle(.plain)
                .disabled(reaction.type == .reactionTypePaid)
                .help(reaction.isChosen ? "Remove reaction" : "React")
            }
        }
    }
}

enum ReactionActions {
    /// Used when a chat allows every reaction, matching Telegram's default palette.
    static let defaultEmoji = ["👍", "❤️", "🔥", "🥰", "👏", "😁", "🤔", "🤯", "😱", "😢", "🎉", "🙏"]

    static func symbol(for type: ReactionType) -> String {
        switch type {
        case .reactionTypeEmoji(let value): value.emoji
        case .reactionTypeCustomEmoji: "✨"
        case .reactionTypePaid: "⭐️"
        }
    }

    /// Emoji offered in the quick reaction menu.
    static func quickReactions(for chat: ChatItem) -> [String] {
        switch chat.availableReactions {
        case .chatAvailableReactionsAll:
            return defaultEmoji
        case .chatAvailableReactionsSome(let value):
            return value.reactions.compactMap {
                if case .reactionTypeEmoji(let emoji) = $0 { return emoji.emoji }
                return nil
            }
        }
    }

    static func toggle(_ type: ReactionType, isChosen: Bool, on message: ChatMessage, session: TelegramSession) {
        let chatId = message.chatId
        let messageId = message.id
        let api = session.api
        Task {
            do {
                if isChosen {
                    try await api.removeMessageReaction(chatId: chatId, messageId: messageId, reactionType: type)
                } else {
                    try await api.addMessageReaction(chatId: chatId, isBig: false, messageId: messageId, reactionType: type, updateRecentReactions: true)
                }
            } catch {
                Log.ui.error("Reaction failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }
}

/// Lays out children left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
