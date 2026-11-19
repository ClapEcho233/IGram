//
//  AppModelTests.swift
//  IGramTests
//

import Foundation
import Testing
@testable import IGram

@MainActor
struct AppModelTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "IGramTests.app.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeApp(_ defaults: UserDefaults) -> AppModel {
        AppModel(credentials: CredentialsStore(defaults: defaults, environment: [:]), defaults: defaults)
    }

    @Test func startsWithOneAccount() {
        let app = makeApp(makeDefaults())
        #expect(app.accountIndices == [0])
        #expect(app.activeIndex == 0)
        #expect(app.canAddAccount)
    }

    @Test func addsAccountsUpToTheLimit() {
        let defaults = makeDefaults()
        let app = makeApp(defaults)
        app.addAccount()
        app.addAccount()
        #expect(app.accountIndices == [0, 1, 2])
        #expect(app.activeIndex == 2)
        #expect(!app.canAddAccount)
        app.addAccount()
        #expect(app.accountIndices.count == AppModel.maxAccounts)

        let reloaded = makeApp(defaults)
        #expect(reloaded.accountIndices == [0, 1, 2])
        #expect(reloaded.activeIndex == 2)
    }

    @Test func switchesOnlyToKnownAccounts() {
        let app = makeApp(makeDefaults())
        app.addAccount()
        app.switchTo(0)
        #expect(app.activeIndex == 0)
        app.switchTo(7)
        #expect(app.activeIndex == 0)
    }
}

@MainActor
struct TDLibEnvironmentTests {
    @Test func accountsGetSeparateDatabases() throws {
        let first = try TDLibEnvironment.current(accountIndex: 0)
        let third = try TDLibEnvironment.current(accountIndex: 2)
        #expect(first.databaseDirectory.path(percentEncoded: false).hasSuffix("IGram/tdlib/db/"))
        #expect(third.databaseDirectory.path(percentEncoded: false).hasSuffix("IGram/tdlib/account-2/db/"))
        #expect(first.filesDirectory != third.filesDirectory)
    }
}
