//
//  InviteLinkSheet.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// A Telegram chat invite link (`t.me/+...` or `t.me/joinchat/...`) awaiting confirmation.
struct InviteLinkRequest: Identifiable, Equatable {
    let id = UUID()
    let link: String
}

/// Preview and confirmation dialog for joining a group or channel via invite link.
struct InviteLinkSheet: View {
    let request: InviteLinkRequest

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.dismiss) private var dismiss

    @State private var info: ChatInviteLinkInfo?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView("Checking invite link…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if let info {
                AvatarView(
                    content: .photo(info.photo, title: info.title, accentColorId: info.accentColorId),
                    size: 72
                )
                VStack(spacing: 4) {
                    Text(info.title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text(memberSummary(info))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !info.description.isEmpty {
                        Text(info.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.top, 4)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack(spacing: 10) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    if info.chatId != 0 {
                        Button("Open Chat") {
                            main.open(chatId: info.chatId)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(joinButtonTitle(info)) {
                            join()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isJoining)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Invalid Invite Link",
                    systemImage: "link.badge.plus",
                    description: Text(errorMessage ?? String(localized: "This invite link has expired or is invalid."))
                )
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .task(id: request.id) { await load() }
    }

    private func memberSummary(_ info: ChatInviteLinkInfo) -> String {
        switch info.type {
        case .inviteLinkChatTypeChannel:
            String(localized: "\(info.memberCount) subscribers")
        default:
            String(localized: "\(info.memberCount) members")
        }
    }

    private func joinButtonTitle(_ info: ChatInviteLinkInfo) -> String {
        if info.createsJoinRequest { return String(localized: "Request to Join") }
        switch info.type {
        case .inviteLinkChatTypeChannel: return String(localized: "Join Channel")
        default: return String(localized: "Join Group")
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            info = try await session.api.checkChatInviteLink(inviteLink: request.link)
        } catch {
            errorMessage = error.telegramMessage
            Log.ui.error("checkChatInviteLink failed: \(error.telegramMessage, privacy: .public)")
        }
        isLoading = false
    }

    private func join() {
        isJoining = true
        errorMessage = nil
        Task {
            defer { isJoining = false }
            do {
                let result = try await session.api.joinChatByInviteLink(inviteLink: request.link)
                switch result {
                case .chatJoinResultSuccess(let value):
                    main.open(chatId: value.chatId)
                    dismiss()
                case .chatJoinResultRequestSent:
                    main.showToast(String(localized: "Join request sent"))
                    dismiss()
                case .chatJoinResultDeclined:
                    errorMessage = String(localized: "Your join request was declined.")
                case .chatJoinResultGuardBotApprovalRequired:
                    main.showToast(String(localized: "Bot approval is required to join this chat."))
                    dismiss()
                }
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }
}
