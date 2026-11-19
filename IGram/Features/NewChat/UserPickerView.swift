//
//  UserPickerView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Contacts and found users to pick from, after tdesktop's
/// `PeerListController` for contacts.
struct UserPickerView: View {
    /// When set, rows toggle membership instead of picking immediately.
    var selection: Binding<Set<Int64>>?
    var onPick: (Int64) -> Void = { _ in }

    @Environment(TelegramSession.self) private var session
    @State private var contacts: [Int64] = []
    @State private var query = ""
    @State private var results: [Int64]?

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            List(results ?? contacts, id: \.self) { userId in
                Button {
                    if let selection {
                        if selection.wrappedValue.contains(userId) {
                            selection.wrappedValue.remove(userId)
                        } else {
                            selection.wrappedValue.insert(userId)
                        }
                    } else {
                        onPick(userId)
                    }
                } label: {
                    row(userId)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if (results ?? contacts).isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No Contacts" : "No Results", systemImage: "person.2")
                }
            }
        }
        .task { await loadContacts() }
        .task(id: query) { await search() }
    }

    private func row(_ userId: Int64) -> some View {
        let item = session.peers.user(userId)
        return HStack(spacing: 10) {
            AvatarView(content: .user(item.user), size: 36, isOnline: DateFormatting.isOnline(item.status))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.fullName).lineLimit(1)
                Text(DateFormatting().presence(item.status))
                    .font(.caption)
                    .foregroundStyle(DateFormatting.isOnline(item.status) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            Spacer()
            if let selection {
                Image(systemName: selection.wrappedValue.contains(userId) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selection.wrappedValue.contains(userId) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    private func loadContacts() async {
        guard let ids = try? await session.api.getContacts().userIds else { return }
        contacts = Self.sorted(ids, session: session)
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        results = (try? await session.api.searchContacts(limit: 50, query: trimmed))?.userIds ?? []
    }

    /// Online first, then most recently seen, then by name, like tdesktop's contacts.
    static func sorted(_ ids: [Int64], session: TelegramSession) -> [Int64] {
        func rank(_ status: UserStatus) -> Int {
            switch status {
            case .userStatusOnline: Int.max
            case .userStatusOffline(let value): value.wasOnline
            case .userStatusRecently: 3
            case .userStatusLastWeek: 2
            case .userStatusLastMonth: 1
            case .userStatusEmpty: 0
            }
        }
        return ids.sorted { a, b in
            let ra = rank(session.peers.user(a).status)
            let rb = rank(session.peers.user(b).status)
            if ra != rb { return ra > rb }
            return session.peers.user(a).fullName.localizedCaseInsensitiveCompare(session.peers.user(b).fullName) == .orderedAscending
        }
    }
}
