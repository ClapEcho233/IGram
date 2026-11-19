//
//  WebAppBridge.swift
//  IGram
//

import AppKit
import Foundation
import SwiftUI
@preconcurrency import TDLibKit

/// Describes how to launch a Telegram Mini App (Web App) through TDLib.
enum WebAppLaunch: Equatable {
    /// Opened from an inline button or bot menu inside a chat (`openWebApp`).
    case chat(botUserId: Int64, chatId: Int64, url: String, topicId: MessageTopic? = nil)
    /// Opened from a reply keyboard or inline query button (`getWebAppUrl`).
    case simple(botUserId: Int64, url: String, buttonText: String?)
    /// A bot's main Mini App from its profile (`getMainWebApp`).
    case mainApp(botUserId: Int64, chatId: Int64, startParameter: String = "")

    var botUserId: Int64 {
        switch self {
        case .chat(let botUserId, _, _, _),
             .simple(let botUserId, _, _),
             .mainApp(let botUserId, _, _):
            botUserId
        }
    }

    var fallbackURL: URL? {
        switch self {
        case .chat(_, _, let url, _), .simple(_, let url, _):
            URL(string: url)
        case .mainApp:
            nil
        }
    }
}

/// A Web App presentation request held by `MainModel`.
struct WebAppRequest: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let launch: WebAppLaunch
}

/// Colors sent to TDLib (`ThemeParameters`) and injected into Mini Apps via
/// `theme_changed`, matching tdesktop's day and night palettes.
nonisolated struct WebAppTheme: Equatable, Sendable {
    let background: Int
    let secondaryBackground: Int
    let headerBackground: Int
    let bottomBarBackground: Int
    let sectionBackground: Int
    let sectionHeaderText: Int
    let sectionSeparator: Int
    let text: Int
    let subtitleText: Int
    let hint: Int
    let link: Int
    let button: Int
    let buttonText: Int
    let accentText: Int
    let destructiveText: Int

    static let light = WebAppTheme(
        background: 0xFFFFFF,
        secondaryBackground: 0xF1F1F1,
        headerBackground: 0xFFFFFF,
        bottomBarBackground: 0xF1F1F1,
        sectionBackground: 0xFFFFFF,
        sectionHeaderText: 0x168ACD,
        sectionSeparator: 0xE7E7E7,
        text: 0x000000,
        subtitleText: 0x707579,
        hint: 0x999999,
        link: 0x168ACD,
        button: 0x40A7E3,
        buttonText: 0xFFFFFF,
        accentText: 0x168ACD,
        destructiveText: 0xD14E4E
    )

    static let dark = WebAppTheme(
        background: 0x17212B,
        secondaryBackground: 0x232E3C,
        headerBackground: 0x17212B,
        bottomBarBackground: 0x17212B,
        sectionBackground: 0x17212B,
        sectionHeaderText: 0x6AB3F3,
        sectionSeparator: 0x101921,
        text: 0xF5F5F5,
        subtitleText: 0x708499,
        hint: 0x708499,
        link: 0x6AB3F3,
        button: 0x5288C1,
        buttonText: 0xFFFFFF,
        accentText: 0x6AB2F2,
        destructiveText: 0xEC3942
    )

    static func current(isDark: Bool) -> WebAppTheme {
        isDark ? .dark : .light
    }

    var tdlibParameters: ThemeParameters {
        ThemeParameters(
            accentTextColor: accentText,
            backgroundColor: background,
            bottomBarBackgroundColor: bottomBarBackground,
            buttonColor: button,
            buttonTextColor: buttonText,
            destructiveTextColor: destructiveText,
            headerBackgroundColor: headerBackground,
            hintColor: hint,
            linkColor: link,
            secondaryBackgroundColor: secondaryBackground,
            sectionBackgroundColor: sectionBackground,
            sectionHeaderTextColor: sectionHeaderText,
            sectionSeparatorColor: sectionSeparator,
            subtitleTextColor: subtitleText,
            textColor: text
        )
    }

    var jsDictionary: [String: String] {
        [
            "bg_color": Self.hex(background),
            "secondary_bg_color": Self.hex(secondaryBackground),
            "header_bg_color": Self.hex(headerBackground),
            "bottom_bar_bg_color": Self.hex(bottomBarBackground),
            "section_bg_color": Self.hex(sectionBackground),
            "section_header_text_color": Self.hex(sectionHeaderText),
            "section_separator_color": Self.hex(sectionSeparator),
            "text_color": Self.hex(text),
            "subtitle_text_color": Self.hex(subtitleText),
            "hint_color": Self.hex(hint),
            "link_color": Self.hex(link),
            "button_color": Self.hex(button),
            "button_text_color": Self.hex(buttonText),
            "accent_text_color": Self.hex(accentText),
            "destructive_text_color": Self.hex(destructiveText),
        ]
    }

    static func hex(_ rgb: Int) -> String {
        String(format: "#%06x", rgb & 0xFFFFFF)
    }

    /// Parses `#RRGGBB` or `RRGGBB` into an RGB integer.
    static func parseHex(_ string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard body.count == 6, let value = Int(body, radix: 16) else { return nil }
        return value
    }

    /// Resolves a Web App color string (`bg_color`, `secondary_bg_color`, `#RRGGBB`).
    func resolve(_ value: String) -> Int? {
        switch value {
        case "bg_color": background
        case "secondary_bg_color": secondaryBackground
        case "bottom_bar_bg_color": bottomBarBackground
        default: Self.parseHex(value)
        }
    }
}

/// State of the Mini App's native bottom button (`MainButton` or `SecondaryButton`).
nonisolated struct WebAppButtonState: Equatable, Sendable {
    var isVisible = false
    var isActive = true
    var isProgressVisible = false
    var text = ""
    var color: Int?
    var textColor: Int?
}

/// A native dialog requested by a Mini App via `web_app_open_popup`.
nonisolated struct WebAppPopup: Identifiable, Equatable, Sendable {
    struct Button: Identifiable, Equatable, Sendable {
        enum Kind: String, Equatable, Sendable {
            case `default`, ok, close, cancel, destructive
        }

        let id: String
        let kind: Kind
        let text: String
    }

    let id = UUID()
    let title: String
    let message: String
    let buttons: [Button]
}

/// Events posted by a Mini App to `window.TelegramWebviewProxy.postEvent`.
nonisolated enum WebAppEvent: Equatable, Sendable {
    case ready
    case close
    case expand
    case requestTheme
    case requestViewport
    case setupMainButton(WebAppButtonState)
    case setupSecondaryButton(WebAppButtonState)
    case setupBackButton(visible: Bool)
    case setupSettingsButton(visible: Bool)
    case setHeaderColor(String)
    case setBackgroundColor(String)
    case setBottomBarColor(String)
    case setupClosingBehavior(needConfirmation: Bool)
    case openLink(url: String)
    case openTelegramLink(pathFull: String)
    case sendData(String)
    case invokeCustomMethod(requestId: String, method: String, paramsJSON: String)
    case openPopup(WebAppPopup)
    case switchInlineQuery(query: String)
    case requestWriteAccess
    case requestPhone
    case hapticFeedback
    case unknown(String)

    static func parse(type: String, rawData: Any?) -> WebAppEvent {
        let object = decodeObject(rawData)
        switch type {
        case "web_app_ready", "iframe_ready":
            return .ready
        case "web_app_close":
            return .close
        case "web_app_expand":
            return .expand
        case "web_app_request_theme":
            return .requestTheme
        case "web_app_request_viewport":
            return .requestViewport
        case "web_app_setup_main_button":
            return .setupMainButton(parseButton(object))
        case "web_app_setup_secondary_button":
            return .setupSecondaryButton(parseButton(object))
        case "web_app_setup_back_button":
            return .setupBackButton(visible: object["is_visible"] as? Bool ?? false)
        case "web_app_setup_settings_button":
            return .setupSettingsButton(visible: object["is_visible"] as? Bool ?? false)
        case "web_app_set_header_color":
            if let color = object["color"] as? String { return .setHeaderColor(color) }
            if let key = object["color_key"] as? String { return .setHeaderColor(key) }
            return .unknown(type)
        case "web_app_set_background_color":
            if let color = object["color"] as? String { return .setBackgroundColor(color) }
            return .unknown(type)
        case "web_app_set_bottom_bar_color":
            if let color = object["color"] as? String { return .setBottomBarColor(color) }
            return .unknown(type)
        case "web_app_setup_closing_behavior":
            return .setupClosingBehavior(needConfirmation: object["need_confirmation"] as? Bool ?? false)
        case "web_app_open_link":
            if let url = object["url"] as? String { return .openLink(url: url) }
            return .unknown(type)
        case "web_app_open_tg_link":
            if let path = object["path_full"] as? String { return .openTelegramLink(pathFull: path) }
            return .unknown(type)
        case "web_app_data_send":
            if let data = object["data"] as? String { return .sendData(data) }
            return .unknown(type)
        case "web_app_invoke_custom_method":
            guard let requestId = object["req_id"] as? String,
                  let method = object["method"] as? String else { return .unknown(type) }
            let paramsValue = object["params"]
            let paramsJSON: String
            if let string = paramsValue as? String {
                paramsJSON = string
            } else if let paramsValue,
                      JSONSerialization.isValidJSONObject(paramsValue),
                      let encoded = try? JSONSerialization.data(withJSONObject: paramsValue),
                      let string = String(data: encoded, encoding: .utf8) {
                paramsJSON = string
            } else {
                paramsJSON = "{}"
            }
            return .invokeCustomMethod(requestId: requestId, method: method, paramsJSON: paramsJSON)
        case "web_app_open_popup":
            guard let message = object["message"] as? String else { return .unknown(type) }
            let title = object["title"] as? String ?? ""
            let rawButtons = object["buttons"] as? [[String: Any]] ?? []
            let buttons = rawButtons.compactMap { item -> WebAppPopup.Button? in
                guard let id = item["id"] as? String else { return nil }
                let kind = WebAppPopup.Button.Kind(rawValue: item["type"] as? String ?? "default") ?? .default
                let text = item["text"] as? String ?? ""
                return WebAppPopup.Button(id: id, kind: kind, text: text)
            }
            return .openPopup(WebAppPopup(title: title, message: message, buttons: buttons))
        case "web_app_switch_inline_query":
            return .switchInlineQuery(query: object["query"] as? String ?? "")
        case "web_app_request_write_access":
            return .requestWriteAccess
        case "web_app_request_phone":
            return .requestPhone
        case "web_app_trigger_haptic_feedback":
            return .hapticFeedback
        default:
            return .unknown(type)
        }
    }

    private static func decodeObject(_ rawData: Any?) -> [String: Any] {
        if let dict = rawData as? [String: Any] { return dict }
        if let string = rawData as? String,
           let data = string.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return [:]
    }

    private static func parseButton(_ object: [String: Any]) -> WebAppButtonState {
        let text = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isVisible = (object["is_visible"] as? Bool ?? false) && !text.isEmpty
        return WebAppButtonState(
            isVisible: isVisible,
            isActive: object["is_active"] as? Bool ?? true,
            isProgressVisible: object["is_progress_visible"] as? Bool ?? false,
            text: text,
            color: (object["color"] as? String).flatMap(WebAppTheme.parseHex),
            textColor: (object["text_color"] as? String).flatMap(WebAppTheme.parseHex)
        )
    }
}

/// Origin checks and JS bridge snippets for `WKWebView`.
nonisolated enum WebAppBridge {
    static let messageHandlerName = "telegramWebApp"

    /// Injected at document start so `telegram-web-app.js` detects native
    /// macOS host support and routes `postEvent` to `WKScriptMessageHandler`.
    static let proxyScript = """
    (function() {
        if (!window.TelegramWebviewProxy) {
            window.TelegramWebviewProxy = {
                postEvent: function(eventType, eventData) {
                    window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                        eventType: String(eventType || ""),
                        eventData: eventData === undefined ? null : eventData
                    });
                }
            };
        }
    })();
    """

    /// Builds a safe JS invocation of `Telegram.WebView.receiveEvent(type, data)`.
    static func receiveEventScript(type: String, payload: [String: Any]? = nil) -> String? {
        guard let encodedType = jsonLiteral(type) else { return nil }
        let encodedPayload: String
        if let payload,
           JSONSerialization.isValidJSONObject(payload),
           let data = try? JSONSerialization.data(withJSONObject: payload),
           let string = String(data: data, encoding: .utf8) {
            encodedPayload = string
        } else {
            encodedPayload = "undefined"
        }
        return "window.Telegram && window.Telegram.WebView && window.Telegram.WebView.receiveEvent(\(encodedType), \(encodedPayload));"
    }

    /// True if both URLs share the same scheme, host and effective port.
    static func sameOrigin(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b,
              let schemeA = a.scheme?.lowercased(), let schemeB = b.scheme?.lowercased(),
              let hostA = a.host()?.lowercased(), let hostB = b.host()?.lowercased() else { return false }
        return schemeA == schemeB && hostA == hostB && effectivePort(a) == effectivePort(b)
    }

    /// Only allow `http` and `https` links from `web_app_open_link`.
    static func safeExternalURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil else { return nil }
        return url
    }

    /// Normalizes a `path_full` from `web_app_open_tg_link` into a `https://t.me/...` URL.
    static func telegramURL(from pathFull: String) -> URL? {
        let path = pathFull.hasPrefix("/") ? pathFull : "/\(pathFull)"
        return URL(string: "https://t.me\(path)")
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    private static func jsonLiteral(_ string: String) -> String? {
        // Wrap in a 1-element array to reuse Foundation's JSON escaping.
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let encoded = String(data: data, encoding: .utf8),
              encoded.count >= 2 else { return nil }
        return String(encoded.dropFirst().dropLast())
    }
}

extension Color {
    /// Creates an sRGB color from a 24-bit `0xRRGGBB` value.
    init(rgb: Int) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}
