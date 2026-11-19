//
//  APICredentials.swift
//  IGram
//

import Foundation
import Observation

/// The `api_id`/`api_hash` pair that identifies a Telegram client application.
///
/// tdesktop compiles its own pair into the binary. Telegram's terms require
/// every third-party client to register its own at https://my.telegram.org,
/// so IGram asks for them at first launch instead of shipping a pair.
nonisolated struct APICredentials: Equatable, Sendable {
    var apiId: Int
    var apiHash: String
    var useTestDC: Bool = false

    static let registrationURL = URL(string: "https://my.telegram.org/apps")!

    /// `api_hash` is always 32 hexadecimal characters.
    var isValid: Bool {
        apiId > 0 && apiHash.count == 32 && apiHash.allSatisfy(\.isHexDigit)
    }

    init(apiId: Int, apiHash: String, useTestDC: Bool = false) {
        self.apiId = apiId
        self.apiHash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.useTestDC = useTestDC
    }
}

/// Loads and persists API credentials.
///
/// The `TG_API_ID` and `TG_API_HASH` environment variables take precedence over
/// saved values, which is convenient when running from Xcode.
@Observable
final class CredentialsStore {
    private(set) var credentials: APICredentials?
    /// True when the credentials come from the environment and cannot be edited in the app.
    private(set) var isFromEnvironment = false

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let apiId = "telegram.apiId"
        static let apiHash = "telegram.apiHash"
        static let useTestDC = "telegram.useTestDC"
    }

    init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        if let id = environment["TG_API_ID"].flatMap(Int.init),
           let hash = environment["TG_API_HASH"] {
            let fromEnvironment = APICredentials(
                apiId: id,
                apiHash: hash,
                useTestDC: environment["TG_TEST_DC"] == "1"
            )
            if fromEnvironment.isValid {
                credentials = fromEnvironment
                isFromEnvironment = true
                return
            }
        }
        let id = defaults.integer(forKey: Key.apiId)
        if let hash = defaults.string(forKey: Key.apiHash) {
            let saved = APICredentials(apiId: id, apiHash: hash, useTestDC: defaults.bool(forKey: Key.useTestDC))
            credentials = saved.isValid ? saved : nil
        }
    }

    func save(_ newValue: APICredentials) {
        precondition(newValue.isValid, "Refusing to save invalid API credentials")
        defaults.set(newValue.apiId, forKey: Key.apiId)
        defaults.set(newValue.apiHash, forKey: Key.apiHash)
        defaults.set(newValue.useTestDC, forKey: Key.useTestDC)
        credentials = newValue
        isFromEnvironment = false
    }

    func clear() {
        defaults.removeObject(forKey: Key.apiId)
        defaults.removeObject(forKey: Key.apiHash)
        defaults.removeObject(forKey: Key.useTestDC)
        credentials = nil
        isFromEnvironment = false
    }
}
