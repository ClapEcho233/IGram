//
//  StorageSettingsView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Cache usage and cleanup, after tdesktop's `Settings::LocalStorage`.
struct StorageSettingsView: View {
    @Environment(TelegramSession.self) private var session
    @State private var statistics: StorageStatisticsFast?
    @State private var isClearing = false
    @State private var isConfirming = false

    var body: some View {
        Form {
            Section("Storage Usage") {
                LabeledContent("Downloaded files", value: statistics.map { DurationFormatting.fileSize($0.filesSize) } ?? "…")
                LabeledContent("Number of files", value: statistics.map { "\($0.fileCount)" } ?? "…")
                LabeledContent("Database", value: statistics.map { DurationFormatting.fileSize($0.databaseSize) } ?? "…")
                LabeledContent("Logs", value: statistics.map { DurationFormatting.fileSize($0.logSize) } ?? "…")
            }
            Section {
                Button(isClearing ? "Clearing…" : "Clear Cache…", role: .destructive) { isConfirming = true }
                    .disabled(isClearing)
            } footer: {
                Text("Media stays in the cloud; you can download it again whenever you need it.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
        .confirmationDialog("Clear all cached media?", isPresented: $isConfirming) {
            Button("Clear Cache", role: .destructive) { clear() }
        }
    }

    private func reload() async {
        statistics = try? await session.api.getStorageStatisticsFast()
    }

    private func clear() {
        isClearing = true
        Task {
            defer { isClearing = false }
            do {
                _ = try await session.api.optimizeStorage(
                    chatIds: nil, chatLimit: 0, count: 0, excludeChatIds: nil, fileTypes: nil,
                    immunityDelay: 0, returnDeletedFileStatistics: false, size: 0, ttl: 0
                )
            } catch {
                Log.ui.error("optimizeStorage failed: \(error.telegramMessage, privacy: .public)")
            }
            await reload()
        }
    }
}
