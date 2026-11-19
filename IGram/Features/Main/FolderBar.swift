//
//  FolderBar.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Chat folders as tabs above the chat list, like tdesktop's folder tabs. A
/// handful of folders doesn't need a whole column, so the window keeps
/// Messages' two columns: conversations and the open chat.
struct FolderBar: View {
    @Bindable var model: MainModel
    @Environment(TelegramSession.self) private var session

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(tabs) { tab in
                        FolderTab(
                            title: tab.title,
                            count: session.chats.list(tab.chatList).unreadUnmutedChatCount,
                            isSelected: selection == tab.sidebarItem
                        ) {
                            model.sidebarSelection = tab.sidebarItem
                        }
                        .id(tab.sidebarItem)
                        .contextMenu { markAsReadButton(tab.chatList) }
                    }
                    FolderTab(
                        title: String(localized: "Archived Chats"),
                        systemImage: "archivebox",
                        count: session.chats.list(.chatListArchive).unreadChatCount,
                        isSelected: selection == .archive
                    ) {
                        model.sidebarSelection = .archive
                    }
                    .id(MainModel.SidebarItem.archive)
                    .contextMenu { markAsReadButton(.chatListArchive) }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .onChange(of: model.sidebarSelection) { _, item in
                guard let item else { return }
                withAnimation(.snappy) { proxy.scrollTo(item, anchor: .center) }
            }
        }
        .onAppear(perform: dropMissingFolder)
        .onChange(of: session.folders.folders.map(\.id)) { dropMissingFolder() }
    }

    private var selection: MainModel.SidebarItem { model.sidebarSelection ?? .allChats }

    /// All Chats alone when there are no folders.
    private var tabs: [ChatFolderTab] {
        let tabs = session.folders.tabs
        return tabs.isEmpty ? [.all] : tabs
    }

    private func markAsReadButton(_ list: ChatList) -> some View {
        Button("Mark All as Read", systemImage: "envelope.open") {
            Task {
                do {
                    try await session.api.readChatList(chatList: list)
                } catch {
                    Log.ui.error("readChatList failed: \(error.telegramMessage, privacy: .public)")
                }
            }
        }
    }

    /// Falls back to All Chats when the remembered folder no longer exists.
    private func dropMissingFolder() {
        guard session.folders.isLoaded, case .folder(let id) = model.sidebarSelection else { return }
        if !session.folders.folders.contains(where: { $0.id == id }) {
            model.sidebarSelection = .allChats
        }
    }
}

/// One folder as a capsule: tinted when selected, with its unread count.
private struct FolderTab: View {
    let title: String
    var systemImage: String?
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(title)
                        .lineLimit(1)
                }
                if count > 0 {
                    Text(UnreadBadge.format(count))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.white))
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint), in: .capsule)
                }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, systemImage == nil ? 12 : 10)
            .frame(height: 28)
            .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
        .accessibilityValue(count > 0 ? Text("\(count) unread") : Text(""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The signed-in account at the bottom of the chat list, with tdesktop's
/// account switcher, Add Account and Settings.
struct AccountFooter: View {
    @Environment(TelegramSession.self) private var session
    @Environment(AppModel.self) private var app

    var body: some View {
        let me = session.me
        Menu {
            ForEach(app.accounts, id: \.index) { account in
                Button {
                    app.switchTo(account.index)
                } label: {
                    if account.index == app.activeIndex {
                        Label(accountTitle(account.session), systemImage: "checkmark")
                    } else {
                        Text(accountTitle(account.session))
                    }
                }
            }
            if app.canAddAccount {
                Divider()
                Button("Add Account", systemImage: "person.badge.plus") { app.addAccount() }
            }
            Divider()
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
        } label: {
            HStack(spacing: 8) {
                AvatarView(content: .user(me.user), size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(me.fullName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(connectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// The account's name, with its unread count when it isn't the one shown.
    private func accountTitle(_ account: TelegramSession) -> String {
        let name = account.me.fullName.isEmpty ? String(localized: "Account") : account.me.fullName
        guard account !== session, account.isAuthorized else { return name }
        let unread = account.chats.list(.chatListMain).unreadUnmutedMessageCount
        return unread > 0 ? "\(name) (\(UnreadBadge.format(unread)))" : name
    }

    private var connectionText: String {
        switch session.connectionState {
        case .connectionStateReady:
            session.me.user?.username.map { "@\($0)" } ?? String(localized: "Online")
        case .connectionStateWaitingForNetwork: String(localized: "Waiting for network…")
        case .connectionStateConnectingToProxy: String(localized: "Connecting to proxy…")
        case .connectionStateConnecting: String(localized: "Connecting…")
        case .connectionStateUpdating: String(localized: "Updating…")
        }
    }
}
