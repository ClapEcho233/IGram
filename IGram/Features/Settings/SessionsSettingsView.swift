//
//  SessionsSettingsView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Active sessions, after tdesktop's `Settings::Sessions`.
struct SessionsSettingsView: View {
    @Environment(TelegramSession.self) private var session
    @State private var sessions: [Session] = []
    @State private var isLoading = true
    @State private var pendingTermination: Session?
    @State private var isConfirmingTerminateAll = false

    var body: some View {
        Form {
            if let current = sessions.first(where: \.isCurrent) {
                Section("This Device") { row(current) }
            }
            let others = sessions.filter { !$0.isCurrent }
            if !others.isEmpty {
                Section {
                    Button("Terminate All Other Sessions", role: .destructive) { isConfirmingTerminateAll = true }
                }
                Section("Active Sessions") {
                    ForEach(others, id: \.id) { item in
                        row(item)
                            .contextMenu {
                                Button("Terminate Session", role: .destructive) { pendingTermination = item }
                            }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .overlay { if isLoading { ProgressView() } }
        .task { await reload() }
        .confirmationDialog("Terminate this session?", item: $pendingTermination) { item in
            Button("Terminate", role: .destructive) {
                Task {
                    _ = try? await session.api.terminateSession(sessionId: item.id)
                    await reload()
                }
            }
        }
        .confirmationDialog("Terminate all other sessions?", isPresented: $isConfirmingTerminateAll) {
            Button("Terminate All", role: .destructive) {
                Task {
                    _ = try? await session.api.terminateAllOtherSessions()
                    await reload()
                }
            }
        }
    }

    private func row(_ item: Session) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(for: item.deviceType))
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.deviceModel.isEmpty ? item.applicationName : item.deviceModel)
                    .font(.body.weight(.medium))
                Text("\(item.applicationName) \(item.applicationVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text([item.location, item.ipAddress].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if item.isCurrent {
                Text("online").font(.caption).foregroundStyle(.tint)
            } else {
                Text(DateFormatting().chatListTimestamp(Date(timeIntervalSince1970: TimeInterval(item.lastActiveDate))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reload() async {
        defer { isLoading = false }
        do {
            sessions = try await session.api.getActiveSessions().sessions
        } catch {
            Log.ui.error("getActiveSessions failed: \(error.telegramMessage, privacy: .public)")
        }
    }

    static func symbol(for type: SessionDeviceType) -> String {
        switch type {
        case .sessionDeviceTypeIphone: "iphone"
        case .sessionDeviceTypeIpad: "ipad"
        case .sessionDeviceTypeMac, .sessionDeviceTypeApple: "laptopcomputer"
        case .sessionDeviceTypeAndroid: "smartphone"
        case .sessionDeviceTypeWindows, .sessionDeviceTypeLinux, .sessionDeviceTypeUbuntu: "desktopcomputer"
        case .sessionDeviceTypeXbox: "gamecontroller"
        case .sessionDeviceTypeChrome, .sessionDeviceTypeFirefox, .sessionDeviceTypeSafari,
             .sessionDeviceTypeEdge, .sessionDeviceTypeOpera, .sessionDeviceTypeBrave, .sessionDeviceTypeVivaldi: "globe"
        case .sessionDeviceTypeUnknown: "questionmark.circle"
        }
    }
}
