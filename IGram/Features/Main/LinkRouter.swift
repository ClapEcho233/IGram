//
//  LinkRouter.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Opens links from message text inside the app when they point at Telegram
/// entities, like tdesktop's `Core::UiIntegration::handleUrlClick`.
struct LinkRouter {
    let session: TelegramSession
    let main: MainModel

    func handle(_ url: URL) -> OpenURLAction.Result {
        if let link = InternalLink(url: url) {
            open(link)
            return .handled
        }
        if let username = Self.telegramUsername(from: url) {
            open(.username(username))
            return .handled
        }
        return .systemAction
    }

    private func open(_ link: InternalLink) {
        Task {
            do {
                switch link {
                case .user(let userId):
                    let chat = try await session.api.createPrivateChat(force: false, userId: userId)
                    main.open(chatId: chat.id)
                case .username(let username):
                    let chat = try await session.api.searchPublicChat(username: username)
                    main.open(chatId: chat.id)
                case .botCommand(let command):
                    // Clicking a command sends it to the open chat, as tdesktop does.
                    guard let chatId = main.selectedChatId else { return }
                    _ = try await session.api.sendMessage(
                        chatId: chatId,
                        inputMessageContent: .inputMessageText(InputMessageText(
                            clearDraft: false,
                            linkPreviewOptions: nil,
                            text: FormattedText(entities: [], text: command)
                        )),
                        options: nil,
                        replyMarkup: nil,
                        replyTo: nil,
                        topicId: nil
                    )
                case .hashtag(let tag):
                    main.searchText = tag
                }
            } catch {
                Log.ui.error("Couldn't open link: \(error.telegramMessage, privacy: .public)")
            }
        }
    }

    /// `https://t.me/name` → `name`, ignoring joinchat/+invite and other special paths.
    static func telegramUsername(from url: URL) -> String? {
        guard let host = url.host()?.lowercased(), ["t.me", "telegram.me", "telegram.dog"].contains(host) else { return nil }
        let components = url.path(percentEncoded: false).split(separator: "/")
        guard components.count == 1, let name = components.first, !name.hasPrefix("+") else { return nil }
        let reserved: Set<String> = ["joinchat", "addstickers", "addemoji", "share", "proxy", "socks", "login", "setlanguage", "confirmphone", "c"]
        guard !reserved.contains(name.lowercased()) else { return nil }
        return String(name)
    }
}
