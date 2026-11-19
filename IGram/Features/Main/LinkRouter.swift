//
//  LinkRouter.swift
//  IGram
//

import AppKit
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
        if let proxy = ProxyDraft(url: url) {
            main.proxyToAdd = proxy
            return .handled
        }
        if let username = Self.telegramUsername(from: url) {
            open(.username(username))
            return .handled
        }
        if Self.isTelegramURL(url) {
            openTelegramURL(url)
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
                    let topic = main.selectedTopic.map { MessageTopic.messageTopicForum(MessageTopicForum(forumTopicId: $0.forumTopicId)) }
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
                        topicId: topic
                    )
                case .hashtag(let tag):
                    main.searchText = tag
                }
            } catch {
                Log.ui.error("Couldn't open link: \(error.telegramMessage, privacy: .public)")
            }
        }
    }

    /// Resolves any `t.me/...` or `tg://...` URL via TDLib's `getInternalLinkType`.
    private func openTelegramURL(_ url: URL) {
        let raw = url.absoluteString
        Task {
            do {
                let resolved = try await session.api.getInternalLinkType(link: raw)
                switch resolved {
                case .internalLinkTypePublicChat(let value):
                    let chat = try await session.api.searchPublicChat(username: value.chatUsername)
                    main.open(chatId: chat.id)
                    if !value.draftText.isEmpty {
                        main.pendingComposerText = MainModel.ComposerDraft(chatId: chat.id, text: value.draftText)
                    }
                    if value.openProfile { main.isInfoPresented = true }
                case .internalLinkTypeMessage(let value):
                    let info = try await session.api.getMessageLinkInfo(url: value.url)
                    if info.chatId != 0 {
                        main.open(chatId: info.chatId, messageId: info.message?.id)
                    }
                case .internalLinkTypeChatInvite(let value):
                    main.inviteLink = InviteLinkRequest(link: value.inviteLink)
                case .internalLinkTypeStickerSet(let value):
                    main.stickerSet = .name(value.stickerSetName)
                case .internalLinkTypeStory(let value):
                    let chat = try await session.api.searchPublicChat(username: value.storyPosterUsername)
                    main.openStory(posterChatId: chat.id, storyId: value.storyId)
                case .internalLinkTypeBotStart(let value):
                    let chat = try await session.api.searchPublicChat(username: value.botUsername)
                    main.open(chatId: chat.id)
                    if case .chatTypePrivate(let privateChat) = chat.type,
                       value.autostart || !value.startParameter.isEmpty {
                        _ = try? await session.api.sendBotStartMessage(
                            botUserId: privateChat.userId,
                            chatId: chat.id,
                            parameter: value.startParameter
                        )
                    }
                case .internalLinkTypeMainWebApp(let value):
                    let chat = try await session.api.searchPublicChat(username: value.botUsername)
                    if case .chatTypePrivate(let privateChat) = chat.type {
                        main.openWebApp(
                            title: chat.title,
                            launch: .mainApp(botUserId: privateChat.userId, chatId: chat.id, startParameter: value.startParameter)
                        )
                    }
                case .internalLinkTypeSavedMessages:
                    guard session.myUserId != 0 else { return }
                    let chat = try await session.api.createPrivateChat(force: false, userId: session.myUserId)
                    main.open(chatId: chat.id)
                default:
                    if url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" {
                        NSWorkspace.shared.open(url)
                    } else {
                        main.showToast(String(localized: "This Telegram link isn't supported yet."))
                    }
                }
            } catch {
                if url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" {
                    NSWorkspace.shared.open(url)
                } else {
                    Log.ui.error("Couldn't resolve Telegram link: \(error.telegramMessage, privacy: .public)")
                }
            }
        }
    }

    static func isTelegramURL(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "tg" { return true }
        guard let host = url.host()?.lowercased() else { return false }
        return ["t.me", "telegram.me", "telegram.dog"].contains(host)
    }

    /// `https://t.me/name` → `name`, ignoring joinchat/+invite and other special paths.
    static func telegramUsername(from url: URL) -> String? {
        guard let host = url.host()?.lowercased(), ["t.me", "telegram.me", "telegram.dog"].contains(host) else { return nil }
        guard url.query() == nil else { return nil }
        let components = url.path(percentEncoded: false).split(separator: "/")
        guard components.count == 1, let name = components.first, !name.hasPrefix("+") else { return nil }
        let reserved: Set<String> = ["joinchat", "addstickers", "addemoji", "share", "proxy", "socks", "login", "setlanguage", "confirmphone", "c"]
        guard !reserved.contains(name.lowercased()) else { return nil }
        return String(name)
    }
}
