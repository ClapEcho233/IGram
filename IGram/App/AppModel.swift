//
//  AppModel.swift
//  IGram
//

import Foundation
import Observation
import OSLog

/// Application-wide state: the API credentials and the current TDLib session.
///
/// tdesktop's `Core::Application` keeps a `Main::Account` alive across log-outs
/// and recreates its session; here a closed TDLib client is replaced by a new
/// `TelegramSession`, which brings the user back to the login screen.
@Observable
final class AppModel {
    let credentials: CredentialsStore
    private(set) var session: TelegramSession?
    /// A session asked to close whose database is still locked by TDLib.
    @ObservationIgnored private var closingSession: TelegramSession?

    init(credentials: CredentialsStore = CredentialsStore()) {
        self.credentials = credentials
        if !Self.isRunningTests {
            startSessionIfPossible()
        }
    }

    /// Saves new credentials and restarts TDLib with them.
    func useCredentials(_ newValue: APICredentials) {
        credentials.save(newValue)
        restartSession()
    }

    /// Forgets the saved credentials and returns to the setup screen.
    func resetCredentials() {
        credentials.clear()
        stopSession()
    }

    /// Flushes TDLib before the app quits.
    func prepareForTermination() {
        session?.close()
    }

    private func startSessionIfPossible() {
        // TDLib locks its database; a new client must wait for the old one to close.
        guard session == nil, closingSession == nil, let credentials = credentials.credentials else { return }
        let session = TelegramSession(credentials: credentials)
        session.onClosed = { [weak self, weak session] in
            guard let self, let session else { return }
            self.sessionDidClose(session)
        }
        self.session = session
        session.start()
        Log.session.info("Started TDLib session")
    }

    private func restartSession() {
        stopSession()
        startSessionIfPossible()
    }

    private func stopSession() {
        guard let session else { return }
        closingSession = session
        session.onClosed = { [weak self] in
            self?.closingSession = nil
            self?.startSessionIfPossible()
        }
        session.close()
        self.session = nil
    }

    private func sessionDidClose(_ closed: TelegramSession) {
        guard session === closed else { return }
        session = nil
        startSessionIfPossible()
    }

    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}
