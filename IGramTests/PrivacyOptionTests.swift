//
//  PrivacyOptionTests.swift
//  IGramTests
//

import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct PrivacyOptionTests {
    private let exception = UserPrivacySettingRule.userPrivacySettingRuleAllowUsers(UserPrivacySettingRuleAllowUsers(userIds: [7]))

    @Test func readsBaseOption() {
        #expect(PrivacyOption.from([.userPrivacySettingRuleAllowAll]) == .everybody)
        #expect(PrivacyOption.from([exception, .userPrivacySettingRuleAllowContacts, .userPrivacySettingRuleRestrictAll]) == .contacts)
        #expect(PrivacyOption.from([.userPrivacySettingRuleRestrictAll]) == .nobody)
        #expect(PrivacyOption.from([]) == .nobody)
    }

    @Test func keepsExceptionsWhenChanging() {
        let rules = PrivacyOption.nobody.rules(keepingExceptionsFrom: [exception, .userPrivacySettingRuleAllowAll])
        #expect(rules == [exception, .userPrivacySettingRuleRestrictAll])
        #expect(PrivacyOption.from(rules) == .nobody)
    }

    @Test func contactsRules() {
        #expect(PrivacyOption.contacts.rules(keepingExceptionsFrom: []) == [.userPrivacySettingRuleAllowContacts, .userPrivacySettingRuleRestrictAll])
    }
}
