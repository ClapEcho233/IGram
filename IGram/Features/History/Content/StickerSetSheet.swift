//
//  StickerSetSheet.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Identifies a sticker set to preview and install or remove.
enum StickerSetTarget: Identifiable, Equatable {
    case id(TdInt64)
    case name(String)

    var id: String {
        switch self {
        case .id(let value): "id:\(value.rawValue)"
        case .name(let name): "name:\(name)"
        }
    }
}

/// Preview sheet for a sticker pack, opened by clicking a sticker in chat or a
/// `t.me/addstickers/...` link, matching tdesktop's `StickerSetBox`.
struct StickerSetSheet: View {
    let target: StickerSetTarget

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.dismiss) private var dismiss

    @State private var set: StickerSet?
    @State private var isLoading = true
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if let set {
                Divider()
                footer(set)
            }
        }
        .frame(width: 420, height: 480)
        .task(id: target) { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(set?.title ?? String(localized: "Stickers"))
                    .font(.headline)
                    .lineLimit(1)
                if let set {
                    Text("\(set.stickers.count) stickers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let set {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                    ForEach(set.stickers, id: \.sticker.id) { sticker in
                        Button {
                            send(sticker)
                        } label: {
                            StickerPreviewCell(sticker: sticker)
                                .frame(width: 68, height: 68)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help(sticker.emoji)
                    }
                }
                .padding(14)
            }
        } else {
            ContentUnavailableView(
                "Sticker Pack Unavailable",
                systemImage: "face.smiling",
                description: Text(errorMessage ?? String(localized: "This sticker pack couldn't be loaded."))
            )
        }
    }

    private func footer(_ set: StickerSet) -> some View {
        HStack {
            Spacer()
            if set.isInstalled {
                Button("Remove Stickers", role: .destructive) {
                    toggleInstalled(set)
                }
                .disabled(isUpdating)
            } else {
                Button("Add \(set.stickers.count) Stickers") {
                    toggleInstalled(set)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating)
            }
        }
        .padding(14)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            switch target {
            case .id(let id):
                set = try await session.api.getStickerSet(setId: id)
            case .name(let name):
                set = try await session.api.searchStickerSet(ignoreCache: false, name: name)
            }
        } catch {
            errorMessage = error.telegramMessage
            Log.ui.error("Loading sticker set failed: \(error.telegramMessage, privacy: .public)")
        }
        isLoading = false
    }

    private func toggleInstalled(_ current: StickerSet) {
        isUpdating = true
        let install = !current.isInstalled
        Task {
            defer { isUpdating = false }
            do {
                _ = try await session.api.changeStickerSet(isArchived: false, isInstalled: install, setId: current.id)
                set = try? await session.api.getStickerSet(setId: current.id)
                main.showToast(install ? String(localized: "Stickers added") : String(localized: "Stickers removed"))
            } catch {
                main.showToast(error.telegramMessage)
            }
        }
    }

    private func send(_ sticker: Sticker) {
        guard let chatId = main.selectedChatId,
              let chat = session.chats.chat(chatId),
              session.composerAvailability(for: chat) == .canSend else { return }
        let topic = main.selectedTopic.map { MessageTopic.messageTopicForum(MessageTopicForum(forumTopicId: $0.forumTopicId)) }
        Task {
            _ = try? await session.api.sendMessage(
                chatId: chatId,
                inputMessageContent: .inputMessageSticker(InputMessageSticker(
                    emoji: sticker.emoji,
                    sticker: InputSticker(
                        height: sticker.height,
                        sticker: .inputFileId(InputFileId(id: sticker.sticker.id)),
                        thumbnail: nil,
                        width: sticker.width
                    )
                )),
                options: nil,
                replyMarkup: nil,
                replyTo: nil,
                topicId: topic
            )
            dismiss()
        }
    }
}

private struct StickerPreviewCell: View {
    let sticker: Sticker

    var body: some View {
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
}
