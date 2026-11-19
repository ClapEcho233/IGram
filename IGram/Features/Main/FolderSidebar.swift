//
//  FolderSidebar.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// The folder column. tdesktop shows folders as a vertical strip next to the
/// chat list; on macOS they become the window's source list.
struct FolderSidebar: View {
    @Bindable var model: MainModel
    @Environment(TelegramSession.self) private var session

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section("Chats") {
                let tabs = session.folders.tabs
                if tabs.isEmpty {
                    row(.all)
                } else {
                    ForEach(tabs) { tab in row(tab) }
                }
            }
            Section {
                Label("Archived Chats", systemImage: "archivebox")
                    .badge(session.chats.list(.chatListArchive).unreadChatCount)
                    .tag(MainModel.SidebarItem.archive)
            }
        }
        .listStyle(.sidebar)
        // A bar rather than an opaque band, so the footer sits on the sidebar's
        // own material like the rest of the column.
        .safeAreaBar(edge: .bottom, spacing: 0) {
            AccountFooter()
        }
        .onAppear(perform: dropMissingFolder)
        .onChange(of: session.folders.folders.map(\.id)) { dropMissingFolder() }
    }

    /// Falls back to All Chats when the remembered folder no longer exists.
    private func dropMissingFolder() {
        guard session.folders.isLoaded, case .folder(let id) = model.sidebarSelection else { return }
        if !session.folders.folders.contains(where: { $0.id == id }) {
            model.sidebarSelection = .allChats
        }
    }

    private func row(_ tab: ChatFolderTab) -> some View {
        let list = session.chats.list(tab.chatList)
        return Label(tab.title, systemImage: tab.systemImage)
            .badge(list.unreadUnmutedChatCount)
            .tag(tab.sidebarItem)
    }
}

/// The signed-in account at the bottom of the sidebar, with tdesktop's
/// account switcher, Add Account and Settings.
private struct AccountFooter: View {
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
