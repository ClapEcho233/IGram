//
//  EnhancementsSettingsView.swift
//  IGram
//

import SwiftUI

/// The extras AyuGram adds to Telegram Desktop: ghost mode, keeping deleted
/// messages and edit history, interface details and streamer mode.
struct EnhancementsSettingsView: View {
    @Environment(TelegramSession.self) private var session
    @Bindable private var features = ExtraFeatures.shared
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                Toggle("Don't Send Read Receipts", isOn: $features.dontReadMessages)
                Toggle("Read Chat After Sending a Message", isOn: $features.readOnSend)
                    .disabled(!features.dontReadMessages)
                    .padding(.leading, 18)
                Toggle("Stay Offline", isOn: $features.stayOffline)
                Toggle("Don't Send Typing Status", isOn: $features.dontSendTyping)
                Toggle("Don't Mark Stories as Viewed", isOn: $features.dontReadStories)
            } header: {
                Text("Ghost Mode")
            } footer: {
                Text("Others won't see that you read their messages, are online, are typing or watched their stories. The eye button above the chat list turns all of these on or off.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep Deleted Messages", isOn: $features.keepDeletedMessages)
                Toggle("Keep Edit History", isOn: $features.keepEditHistory)
                LabeledContent("Kept") {
                    Text("\(session.archive.keptMessageCount) deleted, \(session.archive.editedMessageCount) edited")
                        .foregroundStyle(.secondary)
                }
                Button("Clear Kept Messages…", role: .destructive) {
                    isConfirmingClear = true
                }
                .disabled(session.archive.keptMessageCount == 0 && session.archive.editedMessageCount == 0)
            } header: {
                Text("Message History")
            } footer: {
                Text("Messages others delete stay in the chat, marked as deleted. Click “edited” on a message to see its earlier versions. Only messages received or opened while IGram runs can be kept; they're saved on this Mac only.")
                    .foregroundStyle(.secondary)
            }

            Section("Interface") {
                Toggle("Show Seconds in Message Times", isOn: $features.showSeconds)
                Toggle("Show User, Chat and Message IDs", isOn: $features.showIDs)
                Toggle("Hide Stories", isOn: $features.hideStories)
            }

            Section {
                Toggle("Streamer Mode", isOn: $features.streamerMode)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Hides IGram's windows from screen sharing, recordings and screenshots.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear kept messages?", isPresented: $isConfirmingClear) {
            Button("Clear", role: .destructive) { session.archive.clearAll() }
        } message: {
            Text("Deleted messages and edit history kept for this account will be removed from this Mac.")
        }
    }
}
