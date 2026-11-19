//
//  Attachments.swift
//  IGram
//

import AVFoundation
import Foundation
import OSLog
import UniformTypeIdentifiers
@preconcurrency import TDLibKit

/// A file chosen for sending, copied into the app container so TDLib can read
/// it after security-scoped access ends.
struct PendingAttachment: Identifiable, Equatable {
    enum Kind: Equatable {
        case photo
        case video(duration: Int)
        case animation
        case file
    }

    let id = UUID()
    let url: URL
    let kind: Kind
    let pixelSize: CGSize?

    var fileName: String { url.lastPathComponent }

    var isVisualMedia: Bool {
        switch kind {
        case .photo, .video: true
        case .animation, .file: false
        }
    }

    var fileSize: Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }
}

/// Attachments waiting in the send sheet, like tdesktop's `Ui::PreparedList`.
struct AttachmentBatch: Identifiable {
    let id = UUID()
    var items: [PendingAttachment]

    var hasVisualMedia: Bool { items.contains(where: \.isVisualMedia) }
}

enum AttachmentPreparer {
    /// Telegram sends at most ten items per album.
    static let albumLimit = 10

    /// Copies `urls` into the uploads folder and classifies them.
    static func prepare(_ urls: [URL]) async -> [PendingAttachment] {
        var result: [PendingAttachment] = []
        for url in urls {
            guard let copy = copyToUploads(url) else { continue }
            result.append(await classify(copy))
        }
        return result
    }

    static func uploadsDirectory() throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = caches.appending(path: "IGram/Uploads/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func copyToUploads(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let destination = try uploadsDirectory().appending(path: url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            Log.ui.error("Couldn't copy attachment: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func classify(_ url: URL) async -> PendingAttachment {
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .gif) {
            return PendingAttachment(url: url, kind: .animation, pixelSize: ImagePipeline.pixelSize(of: url))
        }
        if type.conforms(to: .image), let size = ImagePipeline.pixelSize(of: url), max(size.width, size.height) <= 10_000 {
            return PendingAttachment(url: url, kind: .photo, pixelSize: size)
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)).map { Int($0.seconds.rounded()) } ?? 0
            var size: CGSize?
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let natural = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                let rect = CGRect(origin: .zero, size: natural).applying(transform)
                size = CGSize(width: abs(rect.width), height: abs(rect.height))
            }
            return PendingAttachment(url: url, kind: .video(duration: duration), pixelSize: size)
        }
        return PendingAttachment(url: url, kind: .file, pixelSize: nil)
    }

    /// TDLib content for one attachment.
    static func content(for item: PendingAttachment, asFile: Bool, caption: FormattedText?) -> InputMessageContent {
        let file = InputFile.inputFileLocal(InputFileLocal(path: item.url.path(percentEncoded: false)))
        let width = Int(item.pixelSize?.width ?? 0)
        let height = Int(item.pixelSize?.height ?? 0)
        if asFile {
            return .inputMessageDocument(InputMessageDocument(
                caption: caption,
                document: InputDocument(disableContentTypeDetection: false, document: file, thumbnail: nil)
            ))
        }
        switch item.kind {
        case .photo:
            return .inputMessagePhoto(InputMessagePhoto(
                caption: caption,
                hasSpoiler: false,
                photo: InputPhoto(addedStickerFileIds: [], height: height, photo: file, thumbnail: nil, video: nil, width: width),
                selfDestructType: nil,
                showCaptionAboveMedia: false
            ))
        case .video(let duration):
            return .inputMessageVideo(InputMessageVideo(
                caption: caption,
                hasSpoiler: false,
                selfDestructType: nil,
                showCaptionAboveMedia: false,
                video: InputVideo(
                    addedStickerFileIds: [],
                    cover: nil,
                    duration: duration,
                    height: height,
                    startTimestamp: 0,
                    supportsStreaming: true,
                    thumbnail: nil,
                    video: file,
                    width: width
                )
            ))
        case .animation, .file:
            return .inputMessageDocument(InputMessageDocument(
                caption: caption,
                document: InputDocument(disableContentTypeDetection: false, document: file, thumbnail: nil)
            ))
        }
    }

    /// Splits items into sends: photo/video albums of up to ten, other files one by one.
    /// The caption goes on the first message, as Telegram clients do.
    static func plan(_ items: [PendingAttachment], asFiles: Bool, caption: FormattedText?) -> [[InputMessageContent]] {
        var groups: [[InputMessageContent]] = []
        var captionUsed = false
        func nextCaption() -> FormattedText? {
            guard !captionUsed, let caption, !caption.text.isEmpty else { return nil }
            captionUsed = true
            return caption
        }
        if asFiles {
            for item in items { groups.append([content(for: item, asFile: true, caption: nextCaption())]) }
            return groups
        }
        let media = items.filter(\.isVisualMedia)
        let others = items.filter { !$0.isVisualMedia }
        var index = 0
        while index < media.count {
            let chunk = media[index..<min(index + albumLimit, media.count)]
            groups.append(chunk.map { content(for: $0, asFile: false, caption: nextCaption()) })
            index += albumLimit
        }
        for item in others { groups.append([content(for: item, asFile: false, caption: nextCaption())]) }
        return groups
    }
}
