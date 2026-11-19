//
//  Autocomplete.swift
//  IGram
//

import Observation
import SwiftUI
@preconcurrency import TDLibKit

/// Suggestions for the word being typed, after tdesktop's `FieldAutocomplete`:
/// `@` mentions of chat members and `/` bot commands.
@Observable
final class AutocompleteModel {
    enum Kind: Equatable { case mention, command }

    struct Token: Equatable {
        let kind: Kind
        let query: String
        /// Characters to replace at the end of the text, including the trigger.
        let length: Int
    }

    struct Suggestion: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let replacement: String
        /// Set for users without a username: the name becomes a mention entity.
        let mentionUserId: Int64?
        let avatar: AvatarContent?
    }

    private(set) var suggestions: [Suggestion] = []
    private(set) var highlighted = 0
    @ObservationIgnored private var token: Token?

    var isVisible: Bool { !suggestions.isEmpty }

    /// The trigger word at the end of `text`, if any.
    static func token(in text: String) -> Token? {
        if text.hasPrefix("/"), !text.contains(where: \.isWhitespace) {
            let query = String(text.dropFirst())
            guard query.allSatisfy(Self.isWordCharacter) else { return nil }
            return Token(kind: .command, query: query, length: text.count)
        }
        guard let at = text.lastIndex(of: "@") else { return nil }
        let query = String(text[text.index(after: at)...])
        guard query.allSatisfy(Self.isWordCharacter) else { return nil }
        if at != text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        return Token(kind: .mention, query: query, length: query.count + 1)
    }

    nonisolated private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    func update(text: String, chat: ChatItem, session: TelegramSession) async {
        guard let token = Self.token(in: text) else {
            clear()
            return
        }
        self.token = token
        let results: [Suggestion]
        switch token.kind {
        case .command:
            results = commands(in: chat, session: session, matching: token.query)
        case .mention:
            guard chat.isGroup else {
                clear()
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            results = await mentions(in: chat, session: session, matching: token.query)
        }
        guard self.token == token else { return }
        suggestions = Array(results.prefix(8))
        highlighted = 0
    }

    func move(_ delta: Int) -> Bool {
        guard isVisible else { return false }
        highlighted = (highlighted + delta + suggestions.count) % suggestions.count
        return true
    }

    /// Inserts the highlighted (or given) suggestion; returns false if none is shown.
    @discardableResult
    func accept(_ suggestion: Suggestion? = nil, into composer: ComposerModel) -> Bool {
        guard let token, let chosen = suggestion ?? (suggestions.indices.contains(highlighted) ? suggestions[highlighted] : nil) else {
            return false
        }
        composer.replaceSuffix(length: token.length, with: chosen.replacement + " ", mentionUserId: chosen.mentionUserId)
        clear()
        return true
    }

    func clear() {
        suggestions = []
        highlighted = 0
        token = nil
    }

    // MARK: - Sources

    private func commands(in chat: ChatItem, session: TelegramSession, matching query: String) -> [Suggestion] {
        var groups: [BotCommands] = []
        switch chat.type {
        case .chatTypePrivate(let value):
            if let commands = session.peers.user(value.userId).fullInfo?.botInfo?.commands {
                groups = [BotCommands(botUserId: value.userId, commands: commands)]
            }
        case .chatTypeBasicGroup(let value):
            groups = session.peers.basicGroup(value.basicGroupId).fullInfo?.botCommands ?? []
        case .chatTypeSupergroup(let value):
            groups = session.peers.supergroup(value.supergroupId).fullInfo?.botCommands ?? []
        case .chatTypeSecret:
            break
        }
        let lowered = query.lowercased()
        return groups.flatMap { group -> [Suggestion] in
            let bot = session.peers.user(group.botUserId).user
            let suffix = groups.count > 1 ? (bot?.username.map { "@\($0)" } ?? "") : ""
            return group.commands
                .filter { lowered.isEmpty || $0.command.lowercased().hasPrefix(lowered) }
                .map { command in
                    Suggestion(
                        id: "\(group.botUserId)/\(command.command)",
                        title: "/\(command.command)",
                        subtitle: command.description,
                        replacement: "/\(command.command)\(suffix)",
                        mentionUserId: nil,
                        avatar: groups.count > 1 ? .user(bot) : nil
                    )
                }
        }
    }

    private func mentions(in chat: ChatItem, session: TelegramSession, matching query: String) async -> [Suggestion] {
        guard let members = try? await session.api.searchChatMembers(chatId: chat.id, filter: nil, limit: 20, query: query) else {
            return []
        }
        return members.members.compactMap { member in
            guard let userId = member.memberId.userId, userId != session.myUserId,
                  let user = session.peers.user(userId).user, !user.isDeleted else { return nil }
            if let username = user.username {
                return Suggestion(id: "\(userId)", title: user.fullName, subtitle: "@\(username)", replacement: "@\(username)", mentionUserId: nil, avatar: .user(user))
            }
            return Suggestion(id: "\(userId)", title: user.fullName, subtitle: "", replacement: user.fullName, mentionUserId: userId, avatar: .user(user))
        }
    }
}

/// The suggestion list floating above the message field.
struct AutocompleteList: View {
    let model: AutocompleteModel
    let onPick: (AutocompleteModel.Suggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onPick(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        if let avatar = suggestion.avatar {
                            AvatarView(content: avatar, size: 28)
                        }
                        Text(suggestion.title).font(.callout.weight(.medium))
                        Text(suggestion.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(index == model.highlighted ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
