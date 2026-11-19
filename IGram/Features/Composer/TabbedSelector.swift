//
//  TabbedSelector.swift
//  IGram
//

import AppKit
import Observation
import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Stickers and GIFs available to the user, loaded lazily.
@Observable
final class StickerLibrary {
    enum StickerSource: Hashable {
        case recent
        case favorites
        case set(TdInt64)
    }

    private(set) var sets: [StickerSetInfo] = []
    private(set) var stickers: [StickerSource: [Sticker]] = [:]
    private(set) var savedGIFs: [TDLibKit.Animation] = []
    private(set) var gifResults: InlineQueryResults?
    private(set) var isSearchingGIFs = false

    @ObservationIgnored private var gifBotUserId: Int64?

    func loadSets(api: TDLibClient) async {
        guard sets.isEmpty else { return }
        sets = (try? await api.getInstalledStickerSets(stickerType: .stickerTypeRegular))?.sets ?? []
    }

    func load(_ source: StickerSource, api: TDLibClient) async {
        guard stickers[source] == nil else { return }
        switch source {
        case .recent:
            stickers[source] = (try? await api.getRecentStickers(isAttached: false))?.stickers ?? []
        case .favorites:
            stickers[source] = (try? await api.getFavoriteStickers())?.stickers ?? []
        case .set(let id):
            stickers[source] = (try? await api.getStickerSet(setId: id))?.stickers ?? []
        }
    }

    func loadSavedGIFs(api: TDLibClient) async {
        savedGIFs = (try? await api.getSavedAnimations())?.animations ?? []
    }

    /// Searches GIFs through the @gif inline bot, as tdesktop does.
    func searchGIFs(_ query: String, chatId: Int64, api: TDLibClient) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            gifResults = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearchingGIFs = true
        defer { isSearchingGIFs = false }
        do {
            if gifBotUserId == nil {
                let chat = try await api.searchPublicChat(username: "gif")
                if case .chatTypePrivate(let value) = chat.type { gifBotUserId = value.userId }
            }
            guard let bot = gifBotUserId else { return }
            gifResults = try await api.getInlineQueryResults(botUserId: bot, chatId: chatId, offset: "", query: trimmed, userLocation: nil)
        } catch {
            Log.ui.error("GIF search failed: \(error.telegramMessage, privacy: .public)")
        }
    }
}

/// The emoji, sticker and GIF panel, after tdesktop's `ChatHelpers::TabbedSelector`.
struct TabbedSelector: View {
    enum Tab: String, CaseIterable, Identifiable {
        case emoji, stickers, gifs
        var id: String { rawValue }
        var title: String {
            switch self {
            case .emoji: String(localized: "Emoji")
            case .stickers: String(localized: "Stickers")
            case .gifs: String(localized: "GIFs")
            }
        }
    }

    let chatId: Int64
    let composer: ComposerModel
    let library: StickerLibrary
    let onSent: () -> Void

    @AppStorage("tabbedSelector.tab") private var tab = Tab.emoji.rawValue

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()
            switch Tab(rawValue: tab) ?? .emoji {
            case .emoji:
                EmojiGrid { emoji in
                    EmojiCatalog.noteUsed(emoji)
                    composer.insert(emoji)
                }
            case .stickers:
                StickerGrid(composer: composer, library: library, onSent: onSent)
            case .gifs:
                GIFGrid(chatId: chatId, composer: composer, library: library, onSent: onSent)
            }
        }
        .frame(width: 380, height: 440)
    }
}

private struct EmojiCell: Identifiable {
    let section: String
    let emoji: String
    var id: String { section + "/" + emoji }
}

private struct EmojiGrid: View {
    let onPick: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 4), count: 9), alignment: .leading, spacing: 4, pinnedViews: .sectionHeaders) {
                section(id: "recent", String(localized: "Recently Used"), EmojiCatalog.recent)
                ForEach(EmojiCatalog.sections) { section in
                    self.section(id: section.id, section.title, section.emoji)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    /// Emoji repeat between Recently Used and their category, so each cell's
    /// identity includes its section; duplicate ids left blank cells.
    private func section(id: String, _ title: String, _ emoji: [String]) -> some View {
        Section {
            ForEach(emoji.map { EmojiCell(section: id, emoji: $0) }) { cell in
                let item = cell.emoji
                Button {
                    onPick(item)
                } label: {
                    Text(item)
                        .font(.system(size: 26))
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .background(.background)
        }
    }
}

private struct StickerGrid: View {
    let composer: ComposerModel
    let library: StickerLibrary
    let onSent: () -> Void

    @Environment(TelegramSession.self) private var session
    @State private var source: StickerLibrary.StickerSource = .recent

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    sourceButton(.recent) { Image(systemName: "clock").font(.title3) }
                    sourceButton(.favorites) { Image(systemName: "star").font(.title3) }
                    ForEach(library.sets, id: \.id) { set in
                        sourceButton(.set(set.id)) {
                            if let cover = set.covers.first {
                                StickerThumbnail(sticker: cover)
                            } else {
                                Text(String(set.title.prefix(1)))
                            }
                        }
                        .help(set.title)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            Divider()
            ScrollView {
                let stickers = library.stickers[source] ?? []
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(stickers, id: \.sticker.id) { sticker in
                        Button {
                            send(sticker)
                        } label: {
                            StickerThumbnail(sticker: sticker)
                                .frame(width: 64, height: 64)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help(sticker.emoji)
                    }
                }
                .padding(8)
                if library.stickers[source]?.isEmpty == true {
                    Text("No stickers here yet")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
            }
        }
        .task { await library.loadSets(api: session.api) }
        .task(id: source) { await library.load(source, api: session.api) }
    }

    private func sourceButton<Label: View>(_ value: StickerLibrary.StickerSource, @ViewBuilder label: () -> Label) -> some View {
        Button { source = value } label: {
            label()
                .frame(width: 32, height: 32)
                .background(source == value ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func send(_ sticker: Sticker) {
        Task {
            try? await composer.send(.inputMessageSticker(InputMessageSticker(
                emoji: sticker.emoji,
                sticker: InputSticker(
                    height: sticker.height,
                    sticker: .inputFileId(InputFileId(id: sticker.sticker.id)),
                    thumbnail: nil,
                    width: sticker.width
                )
            )))
            onSent()
        }
    }
}

/// A still preview of a sticker for grids, where animating every cell is too costly.
private struct StickerThumbnail: View {
    let sticker: Sticker

    var body: some View {
        if sticker.format == .stickerFormatWebp {
            FileImage(file: sticker.sticker, maxPixelSize: 160, priority: .thumbnail, contentMode: .fit) {
                EmojiPlaceholder(emoji: sticker.emoji, size: 24)
            }
        } else if let thumbnail = sticker.thumbnail, let file = VisualMedia.imageThumbnail(thumbnail) {
            FileImage(file: file, maxPixelSize: 160, priority: .thumbnail, contentMode: .fit) {
                EmojiPlaceholder(emoji: sticker.emoji, size: 24)
            }
        } else {
            EmojiPlaceholder(emoji: sticker.emoji, size: 24)
        }
    }
}

private struct GIFGrid: View {
    let chatId: Int64
    let composer: ComposerModel
    let library: StickerLibrary
    let onSent: () -> Void

    @Environment(TelegramSession.self) private var session
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search GIFs", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    if let results = library.gifResults, !query.isEmpty {
                        ForEach(Array(results.results.enumerated()), id: \.offset) { _, result in
                            if case .inlineQueryResultAnimation(let value) = result {
                                cell(value.animation) { sendResult(value.id, queryId: results.inlineQueryId) }
                            }
                        }
                    } else {
                        ForEach(library.savedGIFs, id: \.animation.id) { animation in
                            cell(animation) { sendSaved(animation) }
                        }
                    }
                }
                .padding(8)
            }
            .overlay {
                if library.isSearchingGIFs {
                    ProgressView()
                } else if query.isEmpty, library.savedGIFs.isEmpty {
                    Text("Saved GIFs appear here").foregroundStyle(.secondary)
                }
            }
        }
        .task { await library.loadSavedGIFs(api: session.api) }
        .task(id: query) { await library.searchGIFs(query, chatId: chatId, api: session.api) }
    }

    private func cell(_ animation: TDLibKit.Animation, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let thumbnail = animation.thumbnail, let file = VisualMedia.imageThumbnail(thumbnail) {
                    FileImage(file: file, maxPixelSize: 240, priority: .thumbnail) {
                        MinithumbnailView(minithumbnail: animation.minithumbnail)
                    }
                } else {
                    MinithumbnailView(minithumbnail: animation.minithumbnail)
                }
            }
            .frame(height: 90)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func sendSaved(_ animation: TDLibKit.Animation) {
        Task {
            try? await composer.send(.inputMessageAnimation(InputMessageAnimation(
                animation: InputAnimation(
                    addedStickerFileIds: [],
                    animation: .inputFileId(InputFileId(id: animation.animation.id)),
                    duration: animation.duration,
                    height: animation.height,
                    thumbnail: nil,
                    width: animation.width
                ),
                caption: nil,
                hasSpoiler: false,
                showCaptionAboveMedia: false
            )))
            onSent()
        }
    }

    private func sendResult(_ resultId: String, queryId: TdInt64) {
        Task {
            try? await composer.sendInlineResult(queryId: queryId, resultId: resultId)
            onSent()
        }
    }
}
