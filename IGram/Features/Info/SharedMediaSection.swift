//
//  SharedMediaSection.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Tabs of shared photos/videos, files, links and voice messages.
struct SharedMediaSection: View {
    let chat: ChatItem
    @Binding var kind: SharedMediaModel.Kind

    @Environment(TelegramSession.self) private var session
    @State private var models: [SharedMediaModel.Kind: SharedMediaModel] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Shared Media", selection: $kind) {
                ForEach(SharedMediaModel.Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let model = models[kind] {
                SharedMediaList(model: model, chat: chat)
            }
        }
        .task(id: kind) {
            if models[kind] == nil {
                models[kind] = SharedMediaModel(chatId: chat.id, kind: kind, api: session.api)
            }
            await models[kind]?.loadMore()
        }
    }
}

private struct SharedMediaList: View {
    let model: SharedMediaModel
    let chat: ChatItem

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.messages.isEmpty, model.isComplete {
                Text("Nothing here yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
            switch model.kind {
            case .media:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                    ForEach(model.messages) { message in
                        VisualMediaView(content: message.content, size: CGSize(width: 92, height: 92))
                            .aspectRatio(1, contentMode: .fill)
                            .contextMenu { showButton(message) }
                    }
                }
            case .files, .voice, .links:
                ForEach(model.messages) { message in
                    row(for: message)
                        .padding(.vertical, 4)
                        .contextMenu { showButton(message) }
                    Divider()
                }
            }
            if !model.isComplete {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .task(id: model.messages.count) { await model.loadMore() }
            }
        }
    }

    @ViewBuilder
    private func row(for message: ChatMessage) -> some View {
        switch message.content {
        case .messageDocument(let value):
            DocumentView(document: value.document, isOutgoingStyle: false)
        case .messageVoiceNote(let value):
            VoiceNoteView(message: message, voiceNote: value.voiceNote, isListened: value.isListened, isOutgoingStyle: false)
        default:
            Button {
                main.open(chatId: chat.id, messageId: message.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.firstLink(in: message) ?? session.formatter().preview(message.content))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                    Text(message.text?.text.singleLine ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func showButton(_ message: ChatMessage) -> some View {
        Button("Show in Chat", systemImage: "text.bubble") {
            main.open(chatId: chat.id, messageId: message.id)
        }
    }

    /// The first URL in a message, for the Links tab.
    static func firstLink(in message: ChatMessage) -> String? {
        guard let text = message.text else { return nil }
        for entity in text.entities {
            switch entity.type {
            case .textEntityTypeTextUrl(let value):
                return value.url
            case .textEntityTypeUrl:
                let utf16 = text.text.utf16
                guard let start = utf16.index(utf16.startIndex, offsetBy: entity.offset, limitedBy: utf16.endIndex),
                      let end = utf16.index(start, offsetBy: entity.length, limitedBy: utf16.endIndex)
                else { continue }
                return String(text.text[start..<end])
            default:
                continue
            }
        }
        return nil
    }
}
