//
//  InlineBotResults.swift
//  IGram
//

import Observation
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// An inline bot query typed at the start of the composer: `@botusername query`.
nonisolated struct InlineQuery: Equatable, Sendable {
    let botUsername: String
    let query: String

    /// Parses `@username <query>` from the beginning of the message field,
    /// matching tdesktop's `InlineBots::Layout::Widget` activation rules.
    static func parse(_ text: String) -> InlineQuery? {
        guard text.hasPrefix("@") else { return nil }
        let rest = text.dropFirst()
        guard let space = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
        let username = String(rest[..<space])
        guard username.count >= 3, username.count <= 32,
              let first = username.first, first.isASCII && first.isLetter,
              username.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
            return nil
        }
        let afterSpace = rest.index(after: space)
        let query = String(rest[afterSpace...])
        return InlineQuery(botUsername: username, query: query)
    }
}

/// Queries any inline bot typed as `@bot query` and holds paginated results.
@Observable
final class InlineResultsModel {
    struct Entry: Identifiable {
        let id: String
        let queryId: TdInt64
        let result: InlineQueryResult
    }

    private struct ResolvedBot {
        let userId: Int64
        let username: String
        let displayName: String
        let placeholder: String
    }

    private(set) var entries: [Entry] = []
    private(set) var button: InlineQueryResultsButton?
    private(set) var nextOffset = ""
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var activeBotUserId: Int64?
    private(set) var activeBotName = ""
    private(set) var placeholder = ""

    @ObservationIgnored private var activeQuery: InlineQuery?
    @ObservationIgnored private var botCache: [String: ResolvedBot?] = [:]

    var isActive: Bool { activeBotUserId != nil }

    var isVisible: Bool {
        activeBotUserId != nil && (isLoading || !entries.isEmpty || button != nil || !placeholder.isEmpty)
    }

    var usesGridLayout: Bool {
        Self.isGridLayout(entries.map(\.result))
    }

    var usesStickerGrid: Bool {
        !entries.isEmpty && entries.allSatisfy {
            if case .inlineQueryResultSticker = $0.result { return true }
            return false
        }
    }

    /// Grid layout when all results are visual media tiles without text descriptions.
    nonisolated static func isGridLayout(_ results: [InlineQueryResult]) -> Bool {
        guard !results.isEmpty else { return false }
        return results.allSatisfy { result in
            switch result {
            case .inlineQueryResultPhoto(let value):
                value.title.isEmpty && value.description.isEmpty
            case .inlineQueryResultAnimation, .inlineQueryResultSticker:
                true
            case .inlineQueryResultVideo(let value):
                value.title.isEmpty && value.description.isEmpty
            default:
                false
            }
        }
    }

    func update(text: String, chatId: Int64, isEditing: Bool, session: TelegramSession) async {
        guard !isEditing, let parsed = InlineQuery.parse(text) else {
            clear()
            return
        }
        let previousBot = activeQuery?.botUsername.lowercased()
        activeQuery = parsed

        guard let bot = await resolveBot(username: parsed.botUsername, session: session) else {
            if activeQuery == parsed { clear() }
            return
        }
        guard !Task.isCancelled, activeQuery == parsed else { return }

        let switchedBot = previousBot != parsed.botUsername.lowercased()
        activeBotUserId = bot.userId
        activeBotName = bot.displayName
        placeholder = bot.placeholder
        if switchedBot {
            entries = []
            button = nil
            nextOffset = ""
        }

        if !switchedBot {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, activeQuery == parsed else { return }
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await session.api.getInlineQueryResults(
                botUserId: bot.userId,
                chatId: chatId,
                offset: "",
                query: parsed.query,
                userLocation: nil
            )
            guard !Task.isCancelled, activeQuery == parsed else { return }
            entries = response.results.map { Entry(id: $0.resultId, queryId: response.inlineQueryId, result: $0) }
            button = response.button
            nextOffset = response.nextOffset
        } catch {
            if !Task.isCancelled {
                Log.ui.error("Inline query failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }

    func loadMore(chatId: Int64, session: TelegramSession) async {
        guard let parsed = activeQuery,
              let botId = activeBotUserId,
              !nextOffset.isEmpty,
              !isLoading,
              !isLoadingMore else { return }
        let offset = nextOffset
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response = try await session.api.getInlineQueryResults(
                botUserId: botId,
                chatId: chatId,
                offset: offset,
                query: parsed.query,
                userLocation: nil
            )
            guard activeQuery == parsed else { return }
            var seen = Set(entries.map(\.id))
            let added = response.results.compactMap { result -> Entry? in
                guard seen.insert(result.resultId).inserted else { return nil }
                return Entry(id: result.resultId, queryId: response.inlineQueryId, result: result)
            }
            entries.append(contentsOf: added)
            nextOffset = added.isEmpty ? "" : response.nextOffset
        } catch {
            Log.ui.error("Inline query paging failed: \(error.telegramMessage, privacy: .public)")
        }
    }

    func clear() {
        activeQuery = nil
        activeBotUserId = nil
        activeBotName = ""
        placeholder = ""
        entries = []
        button = nil
        nextOffset = ""
        isLoading = false
        isLoadingMore = false
    }

    private func resolveBot(username: String, session: TelegramSession) async -> ResolvedBot? {
        let key = username.lowercased()
        if let cached = botCache[key] { return cached }
        guard let chat = try? await session.api.searchPublicChat(username: username),
              case .chatTypePrivate(let value) = chat.type else {
            botCache[key] = nil
            return nil
        }
        let user: User?
        if let cached = session.peers.user(value.userId).user {
            user = cached
        } else {
            user = try? await session.api.getUser(userId: value.userId)
        }
        guard let user, case .userTypeBot(let bot) = user.type, bot.isInline else {
            botCache[key] = nil
            return nil
        }
        let resolved = ResolvedBot(
            userId: user.id,
            username: user.username ?? username,
            displayName: user.fullName.isEmpty ? "@\(username)" : user.fullName,
            placeholder: bot.inlineQueryPlaceholder
        )
        botCache[key] = resolved
        return resolved
    }
}

/// Panel docked above the composer displaying results for `@bot query`.
struct InlineResultsPanel: View {
    let chatId: Int64
    let model: InlineResultsModel
    let composer: ComposerModel

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main

    var body: some View {
        VStack(spacing: 0) {
            if let button = model.button {
                headerButton(button)
                Divider()
            }
            if model.entries.isEmpty {
                emptyState
            } else if model.usesGridLayout {
                gridBody
            } else {
                listBody
            }
        }
        .frame(maxHeight: 240)
    }

    private func headerButton(_ button: InlineQueryResultsButton) -> some View {
        Button {
            handleHeaderButton(button)
        } label: {
            HStack(spacing: 6) {
                Text(button.text)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            if model.isLoading {
                ProgressView().controlSize(.small)
                Text("Searching…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !model.placeholder.isEmpty {
                Text(model.placeholder)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("No results")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 14)
    }

    private var gridBody: some View {
        let columnCount = model.usesStickerGrid ? 6 : 4
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: columnCount)
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(model.entries) { entry in
                    Button {
                        pick(entry)
                    } label: {
                        InlineGridTile(result: entry.result)
                    }
                    .buttonStyle(.plain)
                }
                if !model.nextOffset.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .task(id: model.nextOffset) {
                            await model.loadMore(chatId: chatId, session: session)
                        }
                }
            }
            .padding(8)
        }
    }

    private var listBody: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.entries) { entry in
                    Button {
                        pick(entry)
                    } label: {
                        InlineListRow(result: entry.result)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 64)
                }
                if !model.nextOffset.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .task(id: model.nextOffset) {
                            await model.loadMore(chatId: chatId, session: session)
                        }
                }
            }
        }
    }

    private func pick(_ entry: InlineResultsModel.Entry) {
        model.clear()
        Task {
            do {
                try await composer.sendInlineResult(queryId: entry.queryId, resultId: entry.result.resultId, clearText: true)
            } catch {
                composer.errorMessage = error.telegramMessage
            }
        }
    }

    private func handleHeaderButton(_ button: InlineQueryResultsButton) {
        guard let botId = model.activeBotUserId else { return }
        switch button.type {
        case .inlineQueryResultsButtonTypeStartBot(let start):
            Task {
                if let chat = try? await session.api.createPrivateChat(force: false, userId: botId) {
                    _ = try? await session.api.sendBotStartMessage(botUserId: botId, chatId: chat.id, parameter: start.parameter)
                    main.open(chatId: chat.id)
                }
            }
        case .inlineQueryResultsButtonTypeWebApp(let webApp):
            main.openWebApp(
                title: model.activeBotName.isEmpty ? button.text : model.activeBotName,
                launch: .simple(botUserId: botId, url: webApp.url, buttonText: button.text)
            )
        }
    }
}

private struct InlineGridTile: View {
    let result: InlineQueryResult

    var body: some View {
        Group {
            switch result {
            case .inlineQueryResultPhoto(let value):
                photoTile(value.photo)
            case .inlineQueryResultAnimation(let value):
                animationTile(value.animation)
            case .inlineQueryResultSticker(let value):
                stickerTile(value.sticker)
            case .inlineQueryResultVideo(let value):
                videoTile(value.video)
            default:
                EmptyView()
            }
        }
        .contentShape(.rect)
    }

    private func photoTile(_ photo: Photo) -> some View {
        Group {
            if let file = photo.sizes.last?.photo {
                FileImage(file: file, maxPixelSize: 280, priority: .thumbnail) {
                    MinithumbnailView(minithumbnail: photo.minithumbnail)
                }
            } else {
                MinithumbnailView(minithumbnail: photo.minithumbnail)
            }
        }
        .frame(height: 86)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 6))
    }

    private func animationTile(_ animation: TDLibKit.Animation) -> some View {
        Group {
            if let thumbnail = animation.thumbnail, let file = VisualMedia.imageThumbnail(thumbnail) {
                FileImage(file: file, maxPixelSize: 240, priority: .thumbnail) {
                    MinithumbnailView(minithumbnail: animation.minithumbnail)
                }
            } else {
                MinithumbnailView(minithumbnail: animation.minithumbnail)
            }
        }
        .frame(height: 86)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(alignment: .bottomLeading) {
            MediaBadge(text: "GIF").padding(4)
        }
    }

    private func stickerTile(_ sticker: Sticker) -> some View {
        Group {
            if sticker.format == .stickerFormatWebp {
                FileImage(file: sticker.sticker, maxPixelSize: 160, priority: .thumbnail, contentMode: .fit) {
                    EmojiPlaceholder(emoji: sticker.emoji, size: 28)
                }
            } else if let thumbnail = sticker.thumbnail, let file = VisualMedia.imageThumbnail(thumbnail) {
                FileImage(file: file, maxPixelSize: 160, priority: .thumbnail, contentMode: .fit) {
                    EmojiPlaceholder(emoji: sticker.emoji, size: 28)
                }
            } else {
                EmojiPlaceholder(emoji: sticker.emoji, size: 28)
            }
        }
        .frame(height: 68)
        .frame(maxWidth: .infinity)
    }

    private func videoTile(_ video: Video) -> some View {
        Group {
            if let thumbnail = video.thumbnail, let file = VisualMedia.imageThumbnail(thumbnail) {
                FileImage(file: file, maxPixelSize: 240, priority: .thumbnail) {
                    MinithumbnailView(minithumbnail: video.minithumbnail)
                }
            } else {
                MinithumbnailView(minithumbnail: video.minithumbnail)
            }
        }
        .frame(height: 86)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(alignment: .bottomLeading) {
            MediaBadge(text: DurationFormatting.short(video.duration)).padding(4)
        }
    }
}

private struct InlineListRow: View {
    let result: InlineQueryResult

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 42, height: 42)
                .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let file = thumbnailFile {
            FileImage(file: file, maxPixelSize: 120, priority: .thumbnail) {
                iconBadge
            }
        } else if let minithumbnail {
            MinithumbnailView(minithumbnail: minithumbnail)
        } else {
            iconBadge
        }
    }

    private var iconBadge: some View {
        ZStack {
            Color.accentColor.opacity(0.14)
            Image(systemName: symbolName)
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
        }
    }

    private var thumbnailFile: File? {
        switch result {
        case .inlineQueryResultArticle(let value): value.thumbnail.flatMap(VisualMedia.imageThumbnail)
        case .inlineQueryResultContact(let value): value.thumbnail.flatMap(VisualMedia.imageThumbnail)
        case .inlineQueryResultLocation(let value): value.thumbnail.flatMap(VisualMedia.imageThumbnail)
        case .inlineQueryResultVenue(let value): value.thumbnail.flatMap(VisualMedia.imageThumbnail)
        case .inlineQueryResultGame(let value): value.game.photo.sizes.first?.photo
        case .inlineQueryResultAnimation(let value): value.animation.thumbnail.flatMap(VisualMedia.imageThumbnail)
        case .inlineQueryResultAudio(let value): value.audio.albumCoverThumbnail.flatMap(VisualMedia.imageThumbnail)
        case .inlineQueryResultDocument(let value): value.document.thumbnail.flatMap(VisualMedia.imageThumbnail)
        case .inlineQueryResultPhoto(let value): value.photo.sizes.first?.photo
        case .inlineQueryResultSticker(let value):
            value.sticker.format == .stickerFormatWebp
                ? value.sticker.sticker
                : value.sticker.thumbnail.flatMap(VisualMedia.imageThumbnail)
        case .inlineQueryResultVideo(let value): value.video.thumbnail.flatMap(VisualMedia.imageThumbnail)
        case .inlineQueryResultVoiceNote: nil
        }
    }

    private var minithumbnail: Minithumbnail? {
        switch result {
        case .inlineQueryResultGame(let value): value.game.photo.minithumbnail
        case .inlineQueryResultAnimation(let value): value.animation.minithumbnail
        case .inlineQueryResultAudio(let value): value.audio.albumCoverMinithumbnail
        case .inlineQueryResultDocument(let value): value.document.minithumbnail
        case .inlineQueryResultPhoto(let value): value.photo.minithumbnail
        case .inlineQueryResultVideo(let value): value.video.minithumbnail
        default: nil
        }
    }

    private var symbolName: String {
        switch result {
        case .inlineQueryResultArticle: "doc.text"
        case .inlineQueryResultContact: "person.crop.circle"
        case .inlineQueryResultLocation: "mappin.and.ellipse"
        case .inlineQueryResultVenue: "building.2"
        case .inlineQueryResultGame: "gamecontroller"
        case .inlineQueryResultAnimation: "play.rectangle"
        case .inlineQueryResultAudio: "music.note"
        case .inlineQueryResultDocument: "doc"
        case .inlineQueryResultPhoto: "photo"
        case .inlineQueryResultSticker: "face.smiling"
        case .inlineQueryResultVideo: "film"
        case .inlineQueryResultVoiceNote: "waveform"
        }
    }

    private var title: String {
        switch result {
        case .inlineQueryResultArticle(let value):
            value.title.isEmpty ? value.url : value.title
        case .inlineQueryResultContact(let value):
            [value.contact.firstName, value.contact.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        case .inlineQueryResultLocation(let value):
            value.title.isEmpty ? String(localized: "Location") : value.title
        case .inlineQueryResultVenue(let value):
            value.venue.title
        case .inlineQueryResultGame(let value):
            value.game.title
        case .inlineQueryResultAnimation(let value):
            value.title.isEmpty ? "GIF" : value.title
        case .inlineQueryResultAudio(let value):
            value.audio.title.isEmpty ? value.audio.fileName : value.audio.title
        case .inlineQueryResultDocument(let value):
            value.title.isEmpty ? value.document.fileName : value.title
        case .inlineQueryResultPhoto(let value):
            value.title.isEmpty ? String(localized: "Photo") : value.title
        case .inlineQueryResultSticker(let value):
            value.sticker.emoji.isEmpty ? String(localized: "Sticker") : value.sticker.emoji
        case .inlineQueryResultVideo(let value):
            value.title.isEmpty ? String(localized: "Video") : value.title
        case .inlineQueryResultVoiceNote(let value):
            value.title.isEmpty ? String(localized: "Voice message") : value.title
        }
    }

    private var subtitle: String {
        switch result {
        case .inlineQueryResultArticle(let value):
            value.description.isEmpty ? value.url : value.description
        case .inlineQueryResultContact(let value):
            value.contact.phoneNumber
        case .inlineQueryResultLocation(let value):
            String(format: "%.4f, %.4f", value.location.latitude, value.location.longitude)
        case .inlineQueryResultVenue(let value):
            value.venue.address
        case .inlineQueryResultGame(let value):
            value.game.description
        case .inlineQueryResultAnimation(let value):
            DurationFormatting.short(value.animation.duration)
        case .inlineQueryResultAudio(let value):
            [value.audio.performer, DurationFormatting.short(value.audio.duration)].filter { !$0.isEmpty }.joined(separator: " · ")
        case .inlineQueryResultDocument(let value):
            value.description.isEmpty ? DurationFormatting.fileSize(value.document.document.expectedSize) : value.description
        case .inlineQueryResultPhoto(let value):
            value.description
        case .inlineQueryResultSticker:
            String(localized: "Sticker")
        case .inlineQueryResultVideo(let value):
            value.description.isEmpty ? DurationFormatting.short(value.video.duration) : value.description
        case .inlineQueryResultVoiceNote(let value):
            DurationFormatting.short(value.voiceNote.duration)
        }
    }
}

extension InlineQueryResult {
    var resultId: String {
        switch self {
        case .inlineQueryResultArticle(let value): value.id
        case .inlineQueryResultContact(let value): value.id
        case .inlineQueryResultLocation(let value): value.id
        case .inlineQueryResultVenue(let value): value.id
        case .inlineQueryResultGame(let value): value.id
        case .inlineQueryResultAnimation(let value): value.id
        case .inlineQueryResultAudio(let value): value.id
        case .inlineQueryResultDocument(let value): value.id
        case .inlineQueryResultPhoto(let value): value.id
        case .inlineQueryResultSticker(let value): value.id
        case .inlineQueryResultVideo(let value): value.id
        case .inlineQueryResultVoiceNote(let value): value.id
        }
    }
}
