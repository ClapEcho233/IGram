//
//  PrivacySettingsView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// The "who can…" choice tdesktop shows for each privacy setting.
enum PrivacyOption: String, CaseIterable, Identifiable {
    case everybody, contacts, nobody

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everybody: String(localized: "Everybody")
        case .contacts: String(localized: "My Contacts")
        case .nobody: String(localized: "Nobody")
        }
    }

    /// The base option of a rule list; TDLib evaluates rules in order.
    static func from(_ rules: [UserPrivacySettingRule]) -> PrivacyOption {
        for rule in rules {
            switch rule {
            case .userPrivacySettingRuleAllowAll: return .everybody
            case .userPrivacySettingRuleAllowContacts: return .contacts
            case .userPrivacySettingRuleRestrictAll: return .nobody
            default: continue
            }
        }
        return .nobody
    }

    /// Rules for this option that keep the user's per-person exceptions.
    func rules(keepingExceptionsFrom rules: [UserPrivacySettingRule]) -> [UserPrivacySettingRule] {
        let exceptions = rules.filter { rule in
            switch rule {
            case .userPrivacySettingRuleAllowUsers, .userPrivacySettingRuleAllowChatMembers,
                 .userPrivacySettingRuleRestrictUsers, .userPrivacySettingRuleRestrictChatMembers:
                true
            default:
                false
            }
        }
        let base: [UserPrivacySettingRule] = switch self {
        case .everybody: [.userPrivacySettingRuleAllowAll]
        case .contacts: [.userPrivacySettingRuleAllowContacts, .userPrivacySettingRuleRestrictAll]
        case .nobody: [.userPrivacySettingRuleRestrictAll]
        }
        return exceptions + base
    }
}

/// Privacy and security, after tdesktop's `Settings::PrivacySecurity`.
struct PrivacySettingsView: View {
    @Environment(TelegramSession.self) private var session
    @State private var rules: [UserPrivacySetting: [UserPrivacySettingRule]] = [:]
    @State private var passwordState: PasswordState?
    @State private var blockedCount = 0
    @State private var autoDelete = 0
    @State private var accountTTL = 365
    @State private var isEditingPassword = false
    @State private var isShowingBlocked = false

    private static let settings: [(UserPrivacySetting, LocalizedStringKey)] = [
        (.userPrivacySettingShowPhoneNumber, "Phone Number"),
        (.userPrivacySettingShowStatus, "Last Seen & Online"),
        (.userPrivacySettingShowProfilePhoto, "Profile Photos"),
        (.userPrivacySettingShowBio, "Bio"),
        (.userPrivacySettingShowLinkInForwardedMessages, "Forwarded Messages"),
        (.userPrivacySettingAllowCalls, "Calls"),
        (.userPrivacySettingAllowChatInvites, "Invites to Groups"),
    ]

    var body: some View {
        Form {
            Section("Privacy") {
                ForEach(Self.settings, id: \.0) { setting, title in
                    Picker(title, selection: binding(for: setting)) {
                        ForEach(PrivacyOption.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(rules[setting] == nil)
                }
            }
            Section("Security") {
                LabeledContent("Two-Step Verification") {
                    Button(passwordState?.hasPassword == true ? "Change…" : "Set Up…") { isEditingPassword = true }
                        .disabled(passwordState == nil)
                }
                LabeledContent("Blocked Users") {
                    Button(blockedCount == 0 ? String(localized: "None") : String(localized: "\(blockedCount) blocked…")) {
                        isShowingBlocked = true
                    }
                }
                Picker("Auto-delete new messages", selection: $autoDelete) {
                    Text("Off").tag(0)
                    Text("After 1 day").tag(86_400)
                    Text("After 1 week").tag(604_800)
                    Text("After 1 month").tag(2_678_400)
                }
                .onChange(of: autoDelete) { _, value in
                    Task { try? await session.api.setDefaultMessageAutoDeleteTime(messageAutoDeleteTime: MessageAutoDeleteTime(time: value)) }
                }
                Picker("Delete my account if away for", selection: $accountTTL) {
                    Text("1 month").tag(30)
                    Text("3 months").tag(90)
                    Text("6 months").tag(180)
                    Text("1 year").tag(365)
                    Text("18 months").tag(548)
                    Text("2 years").tag(730)
                }
                .onChange(of: accountTTL) { _, value in
                    Task { try? await session.api.setAccountTtl(ttl: AccountTtl(days: value)) }
                }
            }
        }
        .formStyle(.grouped)
        .task { await load() }
        .sheet(isPresented: $isEditingPassword, onDismiss: { Task { await load() } }) {
            if let passwordState {
                TwoStepVerificationSheet(state: passwordState)
            }
        }
        .sheet(isPresented: $isShowingBlocked, onDismiss: { Task { await load() } }) {
            BlockedUsersSheet()
        }
    }

    private func binding(for setting: UserPrivacySetting) -> Binding<PrivacyOption> {
        Binding(
            get: { PrivacyOption.from(rules[setting] ?? []) },
            set: { option in
                let updated = option.rules(keepingExceptionsFrom: rules[setting] ?? [])
                rules[setting] = updated
                Task {
                    do {
                        try await session.api.setUserPrivacySettingRules(rules: UserPrivacySettingRules(rules: updated), setting: setting)
                    } catch {
                        Log.ui.error("Privacy change failed: \(error.telegramMessage, privacy: .public)")
                    }
                }
            }
        )
    }

    private func load() async {
        let api = session.api
        for (setting, _) in Self.settings {
            if let value = try? await api.getUserPrivacySettingRules(setting: setting) {
                rules[setting] = value.rules
            }
        }
        passwordState = try? await api.getPasswordState()
        blockedCount = (try? await api.getBlockedMessageSenders(blockList: .blockListMain, limit: 1, offset: 0))?.totalCount ?? 0
        autoDelete = (try? await api.getDefaultMessageAutoDeleteTime())?.time ?? 0
        accountTTL = (try? await api.getAccountTtl())?.days ?? 365
    }
}

/// Sets, changes or removes the cloud password, after tdesktop's `PasscodeBox`.
private struct TwoStepVerificationSheet: View {
    let state: PasswordState

    @Environment(TelegramSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var hint = ""
    @State private var recoveryEmail = ""
    @State private var emailCode = ""
    @State private var awaitingEmailCode: EmailAddressAuthenticationCodeInfo?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: String(localized: "Two-Step Verification"), errorMessage: errorMessage) {
                if awaitingEmailCode != nil {
                    Button("Confirm") { confirmEmail() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Save") { save(remove: false) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(newPassword.isEmpty || newPassword != confirmation)
                }
            }
            Form {
                if let info = awaitingEmailCode {
                    Section {
                        TextField("Code", text: $emailCode)
                    } footer: {
                        Text("Enter the code sent to \(info.emailAddressPattern).")
                    }
                } else {
                    if state.hasPassword {
                        SecureField("Current password", text: $currentPassword, prompt: Text(state.passwordHint.isEmpty ? "" : state.passwordHint))
                    }
                    Section {
                        SecureField("New password", text: $newPassword)
                        SecureField("Repeat new password", text: $confirmation)
                        TextField("Hint (optional)", text: $hint)
                    }
                    if !state.hasRecoveryEmailAddress {
                        Section {
                            TextField("Recovery email (optional)", text: $recoveryEmail)
                        } footer: {
                            Text("Lets you reset the password if you forget it.")
                        }
                    }
                    if state.hasPassword {
                        Section {
                            Button("Turn Off Password", role: .destructive) { save(remove: true) }
                                .disabled(currentPassword.isEmpty)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420, height: 480)
    }

    private func save(remove: Bool) {
        Task {
            do {
                let result = try await session.api.setPassword(
                    newHint: remove ? "" : hint,
                    newPassword: remove ? "" : newPassword,
                    newRecoveryEmailAddress: recoveryEmail,
                    oldPassword: currentPassword,
                    setRecoveryEmailAddress: !remove && !recoveryEmail.isEmpty
                )
                if let info = result.recoveryEmailAddressCodeInfo {
                    awaitingEmailCode = info
                } else {
                    dismiss()
                }
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }

    private func confirmEmail() {
        Task {
            do {
                _ = try await session.api.checkRecoveryEmailAddressCode(code: emailCode)
                dismiss()
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }
}

/// Blocked users and chats, after tdesktop's `BlockedBoxController`.
private struct BlockedUsersSheet: View {
    @Environment(TelegramSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var senders: [MessageSender] = []

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: String(localized: "Blocked Users"))
            List(senders, id: \.self) { sender in
                HStack(spacing: 10) {
                    AvatarView(content: session.avatar(of: sender), size: 32)
                    Text(session.displayName(sender)).lineLimit(1)
                    Spacer()
                    Button("Unblock") {
                        Task {
                            _ = try? await session.api.setMessageSenderBlockList(blockList: nil, senderId: sender)
                            await load()
                        }
                    }
                }
            }
            .overlay {
                if senders.isEmpty { ContentUnavailableView("No Blocked Users", systemImage: "hand.raised") }
            }
        }
        .frame(width: 380, height: 440)
        .task { await load() }
    }

    private func load() async {
        senders = (try? await session.api.getBlockedMessageSenders(blockList: .blockListMain, limit: 100, offset: 0))?.senders ?? []
    }
}
