//
//  WebAppTests.swift
//  IGramTests
//

import Foundation
import Testing
@preconcurrency import TDLibKit
@testable import IGram

struct WebAppTests {
    @Test func parsesThemeColorsAndHex() {
        #expect(WebAppTheme.hex(0x40A7E3) == "#40a7e3")
        #expect(WebAppTheme.parseHex("#40A7E3") == 0x40A7E3)
        #expect(WebAppTheme.parseHex("17212b") == 0x17212B)
        #expect(WebAppTheme.parseHex("#fff") == nil)
        #expect(WebAppTheme.light.resolve("bg_color") == WebAppTheme.light.background)
        #expect(WebAppTheme.dark.resolve("secondary_bg_color") == WebAppTheme.dark.secondaryBackground)
        #expect(WebAppTheme.dark.resolve("#112233") == 0x112233)
        #expect(WebAppTheme.dark.jsDictionary["bg_color"] == "#17212b")
        #expect(WebAppTheme.light.tdlibParameters.buttonColor == WebAppTheme.light.button)
    }

    @Test func parsesBridgeEventsFromJSONStringsAndDictionaries() {
        #expect(WebAppEvent.parse(type: "web_app_ready", rawData: nil) == .ready)
        #expect(WebAppEvent.parse(type: "web_app_close", rawData: nil) == .close)
        #expect(WebAppEvent.parse(type: "web_app_expand", rawData: nil) == .expand)
        #expect(WebAppEvent.parse(type: "web_app_setup_back_button", rawData: #"{"is_visible":true}"#) == .setupBackButton(visible: true))
        #expect(WebAppEvent.parse(type: "web_app_setup_closing_behavior", rawData: ["need_confirmation": true]) == .setupClosingBehavior(needConfirmation: true))
        #expect(WebAppEvent.parse(type: "web_app_set_header_color", rawData: #"{"color_key":"secondary_bg_color"}"#) == .setHeaderColor("secondary_bg_color"))
        #expect(WebAppEvent.parse(type: "web_app_open_tg_link", rawData: #"{"path_full":"/durov"}"#) == .openTelegramLink(pathFull: "/durov"))
        #expect(WebAppEvent.parse(type: "web_app_data_send", rawData: #"{"data":"payload"}"#) == .sendData("payload"))
        #expect(WebAppEvent.parse(type: "web_app_switch_inline_query", rawData: #"{"query":"cats"}"#) == .switchInlineQuery(query: "cats"))
    }

    @Test func parsesMainButtonAndHidesWhenTextEmpty() {
        let visible = WebAppEvent.parse(
            type: "web_app_setup_main_button",
            rawData: ##"{"is_visible":true,"is_active":true,"text":"Pay $5","color":"#123456","text_color":"#ffffff"}"##
        )
        #expect(visible == .setupMainButton(WebAppButtonState(
            isVisible: true, isActive: true, isProgressVisible: false,
            text: "Pay $5", color: 0x123456, textColor: 0xFFFFFF
        )))

        let blank = WebAppEvent.parse(
            type: "web_app_setup_main_button",
            rawData: #"{"is_visible":true,"text":"   "}"#
        )
        #expect(blank == .setupMainButton(WebAppButtonState(
            isVisible: false, isActive: true, isProgressVisible: false,
            text: "", color: nil, textColor: nil
        )))
    }

    @Test func parsesCustomMethodAndPopup() {
        let custom = WebAppEvent.parse(
            type: "web_app_invoke_custom_method",
            rawData: #"{"req_id":"r1","method":"getStorageKeys","params":{"a":1}}"#
        )
        if case .invokeCustomMethod(let id, let method, let json) = custom {
            #expect(id == "r1")
            #expect(method == "getStorageKeys")
            #expect(json.contains("\"a\""))
        } else {
            Issue.record("Expected invokeCustomMethod, got \(custom)")
        }

        let popup = WebAppEvent.parse(
            type: "web_app_open_popup",
            rawData: #"{"title":"Confirm","message":"Delete?","buttons":[{"id":"del","type":"destructive","text":"Delete"},{"id":"no","type":"cancel"}]}"#
        )
        if case .openPopup(let parsed) = popup {
            #expect(parsed.title == "Confirm")
            #expect(parsed.message == "Delete?")
            #expect(parsed.buttons.count == 2)
            #expect(parsed.buttons[0].kind == .destructive)
            #expect(parsed.buttons[1].kind == .cancel)
        } else {
            Issue.record("Expected openPopup, got \(popup)")
        }
    }

    @Test func validatesOriginsAndSafeURLs() {
        #expect(WebAppBridge.sameOrigin(URL(string: "https://app.example.com/a"), URL(string: "https://app.example.com:443/b")))
        #expect(!WebAppBridge.sameOrigin(URL(string: "https://app.example.com"), URL(string: "http://app.example.com")))
        #expect(!WebAppBridge.sameOrigin(URL(string: "https://evil.example.com"), URL(string: "https://app.example.com")))

        #expect(WebAppBridge.safeExternalURL(from: "https://telegram.org") == URL(string: "https://telegram.org"))
        #expect(WebAppBridge.safeExternalURL(from: "javascript:alert(1)") == nil)
        #expect(WebAppBridge.safeExternalURL(from: "file:///etc/passwd") == nil)
        #expect(WebAppBridge.telegramURL(from: "durov") == URL(string: "https://t.me/durov"))
        #expect(WebAppBridge.telegramURL(from: "/durov") == URL(string: "https://t.me/durov"))
    }

    @Test func buildsReceiveEventScriptSafely() throws {
        let script = try #require(WebAppBridge.receiveEventScript(type: "theme_changed", payload: ["a": "b\"c"]))
        #expect(script.contains("\"theme_changed\""))
        #expect(script.contains("\\\""))
    }
}
