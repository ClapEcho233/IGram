//
//  APICredentialsTests.swift
//  IGramTests
//

import Foundation
import Testing
@testable import IGram

@MainActor
struct APICredentialsTests {
    private let validHash = "0123456789abcdef0123456789abcdef"

    private func makeDefaults() -> UserDefaults {
        let suite = "IGramTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func validation() {
        #expect(APICredentials(apiId: 12345, apiHash: validHash).isValid)
        #expect(APICredentials(apiId: 12345, apiHash: " \(validHash.uppercased())\n").isValid)
        #expect(!APICredentials(apiId: 0, apiHash: validHash).isValid)
        #expect(!APICredentials(apiId: 12345, apiHash: "short").isValid)
        #expect(!APICredentials(apiId: 12345, apiHash: String(repeating: "z", count: 32)).isValid)
    }

    @Test func emptyStoreHasNoCredentials() {
        let store = CredentialsStore(defaults: makeDefaults(), environment: [:])
        #expect(store.credentials == nil)
    }

    @Test func saveAndReload() {
        let defaults = makeDefaults()
        let store = CredentialsStore(defaults: defaults, environment: [:])
        let credentials = APICredentials(apiId: 42, apiHash: validHash, useTestDC: true)
        store.save(credentials)
        #expect(store.credentials == credentials)

        let reloaded = CredentialsStore(defaults: defaults, environment: [:])
        #expect(reloaded.credentials == credentials)
        #expect(!reloaded.isFromEnvironment)

        reloaded.clear()
        #expect(CredentialsStore(defaults: defaults, environment: [:]).credentials == nil)
    }

    @Test func environmentTakesPrecedence() {
        let defaults = makeDefaults()
        CredentialsStore(defaults: defaults, environment: [:])
            .save(APICredentials(apiId: 1, apiHash: validHash))

        let store = CredentialsStore(
            defaults: defaults,
            environment: ["TG_API_ID": "777", "TG_API_HASH": validHash]
        )
        #expect(store.credentials?.apiId == 777)
        #expect(store.isFromEnvironment)
    }

    @Test func invalidEnvironmentFallsBackToSavedValues() {
        let defaults = makeDefaults()
        CredentialsStore(defaults: defaults, environment: [:])
            .save(APICredentials(apiId: 1, apiHash: validHash))

        let store = CredentialsStore(
            defaults: defaults,
            environment: ["TG_API_ID": "abc", "TG_API_HASH": validHash]
        )
        #expect(store.credentials?.apiId == 1)
        #expect(!store.isFromEnvironment)
    }
}
