//
//  TelegramSession.swift
//  IGram
//

import Foundation
import Observation
import OSLog
@preconcurrency import TDLibKit

/// One TDLib client together with everything it has told us.
///
/// Corresponds to tdesktop's `Main::Session` (account lifetime) combined with
/// `Data::Session` (the cache of peers, chats and files). Every TDLib update is
/// applied here, on the main actor, in the order TDLib produced it.
@Observable
final class TelegramSession {
    @ObservationIgnored let client: TelegramClient
    @ObservationIgnored let credentials: APICredentials
    /// Which account this is; each account has its own TDLib database.
    let accountIndex: Int
    /// True once TDLib started logging this account out.
    private(set) var didLogOut = false

    private(set) var authorizationState: AuthorizationState?
    private(set) var connectionState: ConnectionState = .connectionStateConnecting
    private(set) var myUserId: Int64 = 0
    /// Set when TDLib rejected the start-up parameters.
    private(set) var startupError: String?
    private(set) var isClosed = false

    @ObservationIgnored let peers = PeerStore()
    @ObservationIgnored let files: FileStore
    @ObservationIgnored let chats: ChatStore
    let folders = ChatFolderStore()
    let themes = ThemeStore()

    /// Invoked once after TDLib reports `authorizationStateClosed`.
    @ObservationIgnored var onClosed: (() -> Void)?
    /// Observers that see every update after the stores applied it.
    @ObservationIgnored private var updateObservers: [UUID: (Update) -> Void] = [:]
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var didRequestClose = false
    @ObservationIgnored private var histories: [HistoryKey: WeakHistory] = [:]

    private struct HistoryKey: Hashable {
        let chatId: Int64
        let topicId: Int?
    }

    private struct WeakHistory {
        weak var model: HistoryModel?
    }

    var api: TDLibClient { client.api }

    var isAuthorized: Bool {
        if case .authorizationStateReady = authorizationState { return true }
        return false
    }

    init(credentials: APICredentials, accountIndex: Int = 0, client: TelegramClient = TelegramClient()) {
        self.credentials = credentials
        self.accountIndex = accountIndex
        self.client = client
        files = FileStore(client: client)
        chats = ChatStore(client: client)
    }

    /// Starts consuming TDLib updates. TDLib begins by asking for parameters.
    func start() {
        guard updatesTask == nil else { return }
        let updates = client.updates
        updatesTask = Task { [weak self] in
            for await update in updates {
                guard let self else { return }
                self.handle(update)
            }
            self?.didClose()
        }
    }

    /// Logs out and destroys local data for this account.
    func logOut() async {
        do {
            try await api.logOut()
        } catch {
            Log.session.error("logOut failed: \(error.telegramMessage, privacy: .public)")
        }
    }

    /// Closes the TDLib instance, flushing its database.
    func close() {
        guard !didRequestClose, !isClosed else { return }
        didRequestClose = true
        Task {
            _ = try? await api.close()
        }
    }

    /// The history model for a chat or one of its forum topics, shared while
    /// any view keeps it alive.
    func history(for chatId: Int64, topicId: Int? = nil) -> HistoryModel {
        let key = HistoryKey(chatId: chatId, topicId: topicId)
        if let model = histories[key]?.model { return model }
        let model = HistoryModel(chatId: chatId, topicId: topicId, client: client)
        histories = histories.filter { $0.value.model != nil }
        histories[key] = WeakHistory(model: model)
        return model
    }

    /// Registers `observer` for all updates; returns a token for `removeObserver`.
    @discardableResult
    func addObserver(_ observer: @escaping (Update) -> Void) -> UUID {
        let token = UUID()
        updateObservers[token] = observer
        return token
    }

    func removeObserver(_ token: UUID) {
        updateObservers[token] = nil
    }

    // MARK: - Update routing

    func handle(_ update: Update) {
        if let chatId = update.messageChatId {
            for (key, entry) in histories where key.chatId == chatId {
                entry.model?.handle(update)
            }
        }
        switch update {
        case .updateAuthorizationState(let value):
            handleAuthorizationState(value.authorizationState)
        case .updateConnectionState(let value):
            connectionState = value.state
        case .updateOption(let value):
            handleOption(name: value.name, value: value.value)
        default:
            _ = chats.handle(update) || peers.handle(update) || files.handle(update) || folders.handle(update) || themes.handle(update)
        }
        for observer in updateObservers.values {
            observer(update)
        }
    }

    private func handleAuthorizationState(_ state: AuthorizationState) {
        authorizationState = state
        switch state {
        case .authorizationStateWaitTdlibParameters:
            Task { await sendParameters() }
        case .authorizationStateReady:
            Log.session.info("Authorized")
        case .authorizationStateLoggingOut:
            didLogOut = true
        case .authorizationStateClosed:
            Log.session.info("TDLib closed")
        default:
            break
        }
    }

    private func handleOption(name: String, value: OptionValue) {
        switch (name, value) {
        case ("my_id", .optionValueInteger(let id)):
            myUserId = id.value.rawValue
        case ("my_id", .optionValueEmpty):
            myUserId = 0
        default:
            break
        }
    }

    private func sendParameters() async {
        do {
            let environment = try TDLibEnvironment.current(accountIndex: accountIndex)
            try await api.setTdlibParameters(
                apiHash: credentials.apiHash,
                apiId: credentials.apiId,
                applicationVersion: environment.applicationVersion,
                databaseDirectory: environment.databaseDirectory.path(percentEncoded: false),
                databaseEncryptionKey: Data(),
                deviceModel: environment.deviceModel,
                filesDirectory: environment.filesDirectory.path(percentEncoded: false),
                systemLanguageCode: environment.systemLanguageCode,
                systemVersion: environment.systemVersion,
                useChatInfoDatabase: true,
                useFileDatabase: true,
                useMessageDatabase: true,
                useSecretChats: true,
                useTestDc: credentials.useTestDC
            )
            startupError = nil
        } catch {
            Log.session.error("setTdlibParameters failed: \(error.telegramMessage, privacy: .public)")
            startupError = error.telegramMessage
        }
    }

    private func didClose() {
        guard !isClosed else { return }
        isClosed = true
        updatesTask = nil
        onClosed?()
    }
}
