//
//  SendFilesSheet.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Confirms files before sending, like tdesktop's `SendFilesBox`.
struct SendFilesSheet: View {
    @State var batch: AttachmentBatch
    let composer: ComposerModel

    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var sendAsFiles = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(batch.items) { item in
                        AttachmentTile(item: item) {
                            batch.items.removeAll { $0.id == item.id }
                            if batch.items.isEmpty { dismiss() }
                        }
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 320)

            if batch.hasVisualMedia {
                Toggle("Send as files", isOn: $sendAsFiles)
                    .help("Send without compression")
            }

            TextField("Add a caption…", text: $caption, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    send()
                } label: {
                    if isSending { ProgressView().controlSize(.small) } else { Text("Send") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSending || batch.items.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var title: String {
        let count = batch.items.count
        if batch.items.allSatisfy({ $0.kind == .photo }) && !sendAsFiles {
            return count == 1 ? String(localized: "Send Photo") : String(localized: "Send \(count) Photos")
        }
        return count == 1 ? String(localized: "Send File") : String(localized: "Send \(count) Files")
    }

    private func send() {
        isSending = true
        let items = batch.items
        let asFiles = sendAsFiles
        let rawCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSending = false }
            do {
                let formatted = rawCaption.isEmpty ? nil : try await composer.formattedText(from: rawCaption)
                for group in AttachmentPreparer.plan(items, asFiles: asFiles, caption: formatted) {
                    if group.count > 1 {
                        try await composer.sendAlbum(group)
                    } else if let content = group.first {
                        try await composer.send(content)
                    }
                }
                dismiss()
            } catch {
                errorMessage = error.telegramMessage
                Log.ui.error("Sending files failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }
}

private struct AttachmentTile: View {
    let item: PendingAttachment
    let remove: () -> Void

    @State private var image: CGImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                ZStack {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DocumentView.tint(for: item.fileName))
                        Text(DocumentView.extensionLabel(item.fileName))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    if case .video(let duration) = item.kind {
                        MediaBadge(text: DurationFormatting.short(duration))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(4)
                    }
                }
                .frame(width: 110, height: 90)
                .clipShape(.rect(cornerRadius: 8))
                Text(item.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(DurationFormatting.fileSize(item.fileSize))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(4)
            .help("Remove")
        }
        .task(id: item.url) {
            if item.kind == .photo || item.kind == .animation {
                image = await ImagePipeline.load(item.url, maxPixelSize: 300)
            }
        }
    }
}
