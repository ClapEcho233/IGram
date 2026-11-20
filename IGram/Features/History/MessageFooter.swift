//
//  MessageFooter.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Time, edit mark, views and delivery state in the corner of a bubble.
struct MessageFooter: View {
    let message: ChatMessage
    let chat: ChatItem
    let isOutgoingStyle: Bool
    /// Draws the footer as a dark capsule over media.
    var overMedia = false

    @Environment(TelegramSession.self) private var session
    @Environment(\.chatThemeStyle) private var theme
    @State private var isShowingEdits = false

    var body: some View {
        HStack(spacing: 3) {
            if session.archive.isDeleted(chatId: message.chatId, messageId: message.id) {
                // Kept by Enhancements ▸ Keep Deleted Messages, like AyuGram's mark.
                Image(systemName: "trash")
                    .help("Deleted")
                Text("deleted")
            }
            if let views = message.interactionInfo?.viewCount, views > 0, chat.isChannel {
                Image(systemName: "eye")
                Text(Self.compact(views))
            }
            if message.isEdited {
                editedLabel
            }
            if message.isPinned {
                Image(systemName: "pin.fill")
            }
            Text(DateFormatting().time(message.dateValue, seconds: ExtraFeatures.shared.showSeconds))
            if message.isOutgoing, !chat.isChannel, !session.isSavedMessages(chat) {
                deliveryIcon
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(overMedia ? AnyShapeStyle(.white) : AnyShapeStyle(theme.secondary(outgoing: isOutgoingStyle)))
        .padding(.horizontal, overMedia ? 6 : 0)
        .padding(.vertical, overMedia ? 2 : 0)
        .background {
            if overMedia { Capsule().fill(.black.opacity(0.45)) }
        }
        .fixedSize()
    }

    /// "edited", which shows the earlier versions when the archive kept any.
    @ViewBuilder
    private var editedLabel: some View {
        let versions = session.archive.edits(chatId: message.chatId, messageId: message.id)
        if versions.isEmpty {
            Text("edited")
        } else {
            Button {
                isShowingEdits = true
            } label: {
                Text("edited")
                    .underline()
            }
            .buttonStyle(.plain)
            .help("Show edit history")
            .popover(isPresented: $isShowingEdits, arrowEdge: .bottom) {
                EditHistoryView(versions: versions, current: message.text?.text ?? "", editDate: message.editDate)
            }
        }
    }

    @ViewBuilder
    private var deliveryIcon: some View {
        if message.isFailed {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        } else if message.isSending {
            Image(systemName: "clock")
        } else {
            DeliveryChecks(isRead: message.id <= chat.lastReadOutboxMessageId)
        }
    }

    /// Invisible text reserving room for the footer at the end of the last line,
    /// so short messages keep the time on the same line like tdesktop.
    static func placeholder(for message: ChatMessage, chat: ChatItem, isDeleted: Bool = false, seconds: Bool = false) -> String {
        var parts: [String] = []
        if isDeleted { parts.append("🗑 " + String(localized: "deleted")) }
        if chat.isChannel, let views = message.interactionInfo?.viewCount, views > 0 { parts.append("👁 \(compact(views))") }
        if message.isEdited { parts.append(String(localized: "edited")) }
        if message.isPinned { parts.append("📌") }
        parts.append(DateFormatting().time(message.dateValue, seconds: seconds))
        if message.isOutgoing, !chat.isChannel { parts.append("✓✓") }
        return "\u{2003}" + parts.joined(separator: " ")
    }

    static func compact(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}

/// tdesktop's delivery marks: one check once sent, two once read.
struct DeliveryChecks: View {
    let isRead: Bool

    var body: some View {
        HStack(spacing: -5) {
            Image(systemName: "checkmark")
            if isRead {
                Image(systemName: "checkmark")
            }
        }
        .fontWeight(.semibold)
        .accessibilityElement()
        .accessibilityLabel(isRead ? Text("Read") : Text("Sent"))
    }
}

/// Earlier versions of an edited message, newest first, under the current text.
private struct EditHistoryView: View {
    let versions: [MessageArchive.Edit]
    let current: String
    let editDate: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit History")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    version(current, date: editDate, isCurrent: true)
                    ForEach(versions.reversed()) { edit in
                        Divider()
                        version(edit.text, date: edit.date, isCurrent: false)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(14)
        .frame(width: 320)
    }

    private func version(_ text: String, date: Int, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(isCurrent ? String(localized: "Current") : DateFormatting().dateTime(Date(timeIntervalSince1970: TimeInterval(date))))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Spacer()
            }
            Text(text.isEmpty ? " " : text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
