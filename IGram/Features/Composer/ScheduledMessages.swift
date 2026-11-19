//
//  ScheduledMessages.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Picks when to send a scheduled message, like tdesktop's `ScheduleBox`.
struct ScheduleSheet: View {
    @Binding var date: Date
    let title: String
    let onSchedule: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold())
            DatePicker(
                "Send on",
                selection: $date,
                in: Date.now.addingTimeInterval(60)...Date.now.addingTimeInterval(365 * 86_400),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Schedule") {
                    onSchedule()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// The chat's scheduled messages, after tdesktop's `ScheduledWidget`.
struct ScheduledMessagesSheet: View {
    let chat: ChatItem

    @Environment(TelegramSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [Message] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scheduled Messages").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            List(messages, id: \.id) { message in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sendTime(of: message))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                        Text(session.formatter().preview(message.content))
                            .lineLimit(3)
                    }
                    Spacer()
                    Button("Send Now") { sendNow(message) }
                        .controlSize(.small)
                    Button(role: .destructive) {
                        delete(message)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if isLoading {
                    ProgressView()
                } else if messages.isEmpty {
                    ContentUnavailableView("No Scheduled Messages", systemImage: "calendar.badge.clock")
                }
            }
        }
        .frame(width: 440, height: 420)
        .task { await reload() }
    }

    private func sendTime(of message: Message) -> String {
        switch message.schedulingState {
        case .messageSchedulingStateSendAtDate(let value):
            let date = Date(timeIntervalSince1970: TimeInterval(value.sendDate))
            return "\(DateFormatting().daySeparator(date)) \(DateFormatting().time(date))"
        case .messageSchedulingStateSendWhenOnline:
            return String(localized: "When online")
        default:
            return ""
        }
    }

    private func reload() async {
        defer { isLoading = false }
        messages = (try? await session.api.getChatScheduledMessages(chatId: chat.id))?.messages ?? []
    }

    private func sendNow(_ message: Message) {
        Task {
            do {
                try await session.api.editMessageSchedulingState(chatId: chat.id, messageId: message.id, schedulingState: nil)
            } catch {
                Log.ui.error("Send now failed: \(error.telegramMessage, privacy: .public)")
            }
            await reload()
        }
    }

    private func delete(_ message: Message) {
        Task {
            _ = try? await session.api.deleteMessages(chatId: chat.id, messageIds: [message.id], revoke: true)
            await reload()
        }
    }
}
