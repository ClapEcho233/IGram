//
//  SendOptionsTests.swift
//  IGramTests
//

import Foundation
import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct SendOptionsTests {
    @Test func standardSendsWithoutOptions() {
        #expect(ComposerModel.SendOptions.standard.messageSendOptions == nil)
    }

    @Test func silent() {
        let options = ComposerModel.SendOptions(isSilent: true).messageSendOptions
        #expect(options?.disableNotification == true)
        #expect(options?.schedulingState == nil)
    }

    @Test func scheduledAtDate() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let options = ComposerModel.SendOptions(scheduleDate: date).messageSendOptions
        #expect(options?.schedulingState == .messageSchedulingStateSendAtDate(MessageSchedulingStateSendAtDate(repeatPeriod: 0, sendDate: 1_800_000_000)))
    }

    @Test func whenOnline() {
        #expect(ComposerModel.SendOptions(whenOnline: true).messageSendOptions?.schedulingState == .messageSchedulingStateSendWhenOnline)
    }
}
