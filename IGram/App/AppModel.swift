//
//  AppModel.swift
//  IGram
//

import Foundation
import Observation
import OSLog

/// Application-wide state: the API credentials and one TDLib session per
/// account.
///
/// Like tdesktop's `Core::Application` with its `Main::Domain`, IGram keeps up
/// to three accounts, each in its own TDLib database. A closed TDLib client is
/// replaced by a new `TelegramSession`, which brings that account back to the
/// login screen, or removes the account when it logged out and others remain.
@Observable
final class AppModel {
    static let maxAccounts = 3

    let credentials: CredentialsStore
    private(set) var accountIndices: [Int]
    private(set) var sessions: [Int: TelegramSession] = [:]
    private(set) var activeIndex: Int

    /// Accounts whose TDLib database is still locked by a closing client.
    @ObservationIgnored private var closingIndices: Set<Int> = []
    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let indices = "accounts.indices"
        static let active = "accounts.active"
    }

    init(credentials: CredentialsStore = CredentialsStore(), defaults: UserDefaults = .standard) {
        self.credentials = credentials
        self.defaults = defaults
        let saved = (defaults.array(forKey: Key.indices) as? [Int]) ?? []
        let indices = saved.isEmpty ? [0] : saved
        let active = defaults.integer(forKey: Key.active)
        accountIndices = indices
        activeIndex = indices.contains(active) ? active : indices[0]
        if !Self.isRunningTests {
            accountIndices.forEach(start)
        }
    }

    /// The session of the account shown in the window.
    var session: TelegramSession? { sessions[activeIndex] }

    var canAddAccount: Bool { accountIndices.count < Self.maxAccounts }

    /// Accounts in display order, for the account switcher.
    var accounts: [(index: Int, session: TelegramSession)] {
        accountIndices.compactMap { index in sessions[index].map { (index, $0) } }
    }

    // MARK: - Accounts

    func switchTo(_ index: Int) {
        guard accountIndices.contains(index) else { return }
        activeIndex = index
        persist()
    }

    /// Opens the login flow for another account, keeping the current ones.
    func addAccount() {
        guard canAddAccount else { return }
        let index = (accountIndices.max() ?? -1) + 1
        accountIndices.append(index)
        activeIndex = index
        persist()
        start(index)
    }

    /// Abandons an unfinished login started with `addAccount()`.
    func cancelAddingAccount() {
        guard let session, !session.isAuthorized, accountIndices.count > 1 else { return }
        let index = activeIndex
        accountIndices.removeAll { $0 == index }
        activeIndex = accountIndices[0]
        persist()
        // Logging out an unauthorized client also deletes its database.
        Task { await session.logOut() }
    }

    // MARK: - Credentials

    /// Saves new credentials and restarts every account with them.
    func useCredentials(_ newValue: APICredentials) {
        credentials.save(newValue)
        stopAll()
        accountIndices.forEach(start)
    }

    /// Forgets the saved credentials and returns to the setup screen.
    func resetCredentials() {
        credentials.clear()
        stopAll()
    }

    /// Flushes TDLib before the app quits.
    func prepareForTermination() {
        sessions.values.forEach { $0.close() }
    }

    // MARK: - Session lifecycle

    private func start(_ index: Int) {
        // TDLib locks its database; a new client must wait for the old one to close.
        guard sessions[index] == nil, !closingIndices.contains(index), let credentials = credentials.credentials else { return }
        let session = TelegramSession(credentials: credentials, accountIndex: index)
        session.onClosed = { [weak self, weak session] in
            guard let self, let session else { return }
            self.sessionDidClose(session, index: index)
        }
        sessions[index] = session
        session.start()
        Log.session.info("Started TDLib session for account \(index)")
    }

    private func stopAll() {
        for (index, session) in sessions {
            closingIndices.insert(index)
            session.onClosed = { [weak self] in
                guard let self else { return }
                self.closingIndices.remove(index)
                if self.accountIndices.contains(index) { self.start(index) }
            }
            session.close()
        }
        sessions = [:]
    }

    private func sessionDidClose(_ closed: TelegramSession, index: Int) {
        guard sessions[index] === closed else { return }
        sessions[index] = nil
        if closed.didLogOut, accountIndices.count > 1, accountIndices.contains(index) {
            accountIndices.removeAll { $0 == index }
            if activeIndex == index {
                activeIndex = accountIndices.first { sessions[$0]?.isAuthorized == true } ?? accountIndices[0]
            }
            persist()
            return
        }
        if accountIndices.contains(index) { start(index) }
    }

    private func persist() {
        defaults.set(accountIndices, forKey: Key.indices)
        defaults.set(activeIndex, forKey: Key.active)
    }

    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}
