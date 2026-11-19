//
//  SelectionBar.swift
//  IGram
//

import AppKit
import SwiftUI
@preconcurrency import TDLibKit

/// Replaces the composer while messages are selected, with tdesktop's
/// selection actions: copy, forward and delete.
struct SelectionBar: View {
    let actions: MessageActionsModel
    let history: HistoryModel
    let chat: ChatItem

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main

    var body: some View {
        let messages = actions.selectedMessages(in: history)
        let properties = messages.compactMap { history.properties[$0.id] }
        let complete = properties.count == messages.count
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                Button("Cancel") { actions.clearSelection() }
                    .keyboardShortcut(.cancelAction)
                Text(messages.count == 1 ? String(localized: "1 message selected") : String(localized: "\(messages.count) messages selected"))
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { copy(messages) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Forward", systemImage: "arrowshape.turn.up.right") {
                    actions.forwarding = .init(messages: messages)
                    actions.clearSelection()
                }
                .disabled(!complete || !properties.allSatisfy(\.canBeForwarded))
                Button("Delete", systemImage: "trash", role: .destructive) {
                    actions.deletion = .init(
                        messages: messages,
                        canDeleteForEveryone: properties.allSatisfy(\.canBeDeletedForAllUsers),
                        canDeleteForSelf: properties.allSatisfy(\.canBeDeletedOnlyForSelf)
                    )
                    actions.clearSelection()
                }
                .disabled(!complete || !properties.allSatisfy { $0.canBeDeletedForAllUsers || $0.canBeDeletedOnlyForSelf })
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
        }
        .background(.bar)
    }

    /// Copies messages as "Name, [date]:\ntext" blocks, like tdesktop.
    private func copy(_ messages: [ChatMessage]) {
        let formatter = session.formatter(history: history)
        let dates = DateFormatting()
        let text = messages.map { message -> String in
            let body = message.isService
                ? formatter.serviceText(for: message)
                : (message.text?.text.isEmpty == false ? message.text!.text : formatter.preview(message.content))
            if messages.count == 1 { return body }
            let header = "\(session.displayName(message.senderId)), [\(dates.chatListTimestamp(message.dateValue)) \(dates.time(message.dateValue))]"
            return "\(header)\n\(body)"
        }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        main.showToast(String(localized: "Copied to clipboard"))
    }
}
