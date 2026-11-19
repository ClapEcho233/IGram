//
//  FileStore.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// Observable state of one TDLib file (photo size, document, avatar…).
@Observable
final class FileItem: Identifiable {
    let id: Int
    private(set) var file: File

    init(file: File) {
        id = file.id
        self.file = file
    }

    fileprivate func apply(_ file: File) { self.file = file }

    var isDownloaded: Bool { file.local.isDownloadingCompleted && !file.local.path.isEmpty }
    var isDownloading: Bool { file.local.isDownloadingActive }
    var isUploading: Bool { file.remote.isUploadingActive }

    var localURL: URL? {
        isDownloaded ? URL(filePath: file.local.path) : nil
    }

    /// Total size in bytes, falling back to TDLib's estimate when unknown.
    var totalSize: Int64 { file.size > 0 ? file.size : file.expectedSize }

    /// Download or upload progress in `0...1`.
    var progress: Double {
        let total = Double(totalSize)
        guard total > 0 else { return 0 }
        let done = isUploading ? Double(file.remote.uploadedSize) : Double(file.local.downloadedSize)
        return min(max(done / total, 0), 1)
    }
}

/// Tracks files and their downloads, like tdesktop's `Data::DocumentMedia`
/// and download manager. Progress arrives through `updateFile`.
final class FileStore {
    /// TDLib download priorities range from 1 (lowest) to 32 (highest).
    enum Priority: Int {
        case background = 1
        case thumbnail = 8
        case media = 16
        case userInitiated = 32
    }

    private let client: TelegramClient
    private var items: [Int: FileItem] = [:]

    init(client: TelegramClient) {
        self.client = client
    }

    /// Returns the item for `file`, registering it on first sight. Later
    /// `updateFile` updates win over stale snapshots embedded in messages.
    func item(for file: File) -> FileItem {
        if let item = items[file.id] { return item }
        let item = FileItem(file: file)
        items[file.id] = item
        return item
    }

    func item(id: Int) -> FileItem? { items[id] }

    /// Starts downloading `file` unless it is already local or in progress.
    func download(_ file: File, priority: Priority = .media) {
        let item = item(for: file)
        guard !item.isDownloaded, !item.isDownloading, item.file.local.canBeDownloaded else { return }
        let fileId = file.id
        let api = client.api
        Task {
            do {
                let updated = try await api.downloadFile(
                    fileId: fileId,
                    limit: 0,
                    offset: 0,
                    priority: priority.rawValue,
                    synchronous: false
                )
                self.apply(updated)
            } catch {
                Log.data.error("downloadFile \(fileId) failed: \(error.telegramMessage, privacy: .public)")
            }
        }
    }

    /// Downloads `file` and waits until it is fully available locally.
    func downloadedURL(for file: File, priority: Priority = .userInitiated) async throws -> URL {
        if let url = item(for: file).localURL { return url }
        let updated = try await client.api.downloadFile(
            fileId: file.id,
            limit: 0,
            offset: 0,
            priority: priority.rawValue,
            synchronous: true
        )
        apply(updated)
        guard let url = item(for: updated).localURL else {
            throw TDError(code: 400, message: "FILE_DOWNLOAD_FAILED")
        }
        return url
    }

    func cancelDownload(_ file: File) {
        let api = client.api
        let fileId = file.id
        Task { _ = try? await api.cancelDownloadFile(fileId: fileId, onlyIfPending: false) }
    }

    @discardableResult
    func handle(_ update: Update) -> Bool {
        guard case .updateFile(let value) = update else { return false }
        apply(value.file)
        return true
    }

    private func apply(_ file: File) {
        if let item = items[file.id] {
            item.apply(file)
        } else {
            items[file.id] = FileItem(file: file)
        }
    }
}
