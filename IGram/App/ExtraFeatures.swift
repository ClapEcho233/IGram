//
//  ExtraFeatures.swift
//  IGram
//

import AppKit
import Foundation
import Observation

/// The extras AyuGram adds to the official client, toggled in
/// Settings ▸ Enhancements: ghost mode, keeping deleted messages and edit
/// history, interface details, and streamer mode.
///
/// An observable object rather than `@AppStorage`, so views only re-render
/// when one of these toggles changes, not on every defaults write.
@Observable
final class ExtraFeatures {
    static let shared = ExtraFeatures()

    /// Posted when a setting that changes what is sent to Telegram (online
    /// status) or how windows are shared (streamer mode) changes.
    static let didChangeNotification = Notification.Name("IGramExtraFeaturesDidChange")

    enum Key {
        static let dontReadMessages = "extras.ghost.dontReadMessages"
        static let readOnSend = "extras.ghost.readOnSend"
        static let stayOffline = "extras.ghost.stayOffline"
        static let dontSendTyping = "extras.ghost.dontSendTyping"
        static let dontReadStories = "extras.ghost.dontReadStories"
        static let keepDeletedMessages = "extras.history.keepDeletedMessages"
        static let keepEditHistory = "extras.history.keepEditHistory"
        static let showSeconds = "extras.interface.showSeconds"
        static let showIDs = "extras.interface.showIDs"
        static let hideStories = "extras.interface.hideStories"
        static let streamerMode = "extras.privacy.streamerMode"
    }

    // MARK: Ghost mode

    /// Opening a chat doesn't mark its messages as read for the sender.
    var dontReadMessages: Bool { didSet { store(dontReadMessages, Key.dontReadMessages) } }
    /// With `dontReadMessages`, sending a message still reads the chat.
    var readOnSend: Bool { didSet { store(readOnSend, Key.readOnSend) } }
    /// Never reports the account as online.
    var stayOffline: Bool { didSet { store(stayOffline, Key.stayOffline, notify: true) } }
    /// Doesn't send "typing…" or "recording voice…".
    var dontSendTyping: Bool { didSet { store(dontSendTyping, Key.dontSendTyping) } }
    /// Watching a story doesn't add you to its viewers.
    var dontReadStories: Bool { didSet { store(dontReadStories, Key.dontReadStories) } }

    // MARK: Message history

    /// Messages others delete stay in the history, marked as deleted.
    var keepDeletedMessages: Bool { didSet { store(keepDeletedMessages, Key.keepDeletedMessages) } }
    /// Earlier versions of edited messages are kept and shown on request.
    var keepEditHistory: Bool { didSet { store(keepEditHistory, Key.keepEditHistory) } }

    // MARK: Interface

    var showSeconds: Bool { didSet { store(showSeconds, Key.showSeconds) } }
    /// User, chat and message IDs in the info panel and message menus.
    var showIDs: Bool { didSet { store(showIDs, Key.showIDs) } }
    var hideStories: Bool { didSet { store(hideStories, Key.hideStories) } }

    // MARK: Privacy

    /// Hides IGram's windows from screen sharing and screenshots.
    var streamerMode: Bool { didSet { store(streamerMode, Key.streamerMode, notify: true) } }

    /// Whether any ghost mode option is on, for the indicator in the chat list.
    var isGhostModeActive: Bool {
        dontReadMessages || stayOffline || dontSendTyping || dontReadStories
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dontReadMessages = defaults.bool(forKey: Key.dontReadMessages)
        readOnSend = defaults.object(forKey: Key.readOnSend) as? Bool ?? true
        stayOffline = defaults.bool(forKey: Key.stayOffline)
        dontSendTyping = defaults.bool(forKey: Key.dontSendTyping)
        dontReadStories = defaults.bool(forKey: Key.dontReadStories)
        keepDeletedMessages = defaults.bool(forKey: Key.keepDeletedMessages)
        keepEditHistory = defaults.bool(forKey: Key.keepEditHistory)
        showSeconds = defaults.bool(forKey: Key.showSeconds)
        showIDs = defaults.bool(forKey: Key.showIDs)
        hideStories = defaults.bool(forKey: Key.hideStories)
        streamerMode = defaults.bool(forKey: Key.streamerMode)
    }

    /// Turns every ghost mode option on or off at once.
    func setGhostMode(_ isOn: Bool) {
        dontReadMessages = isOn
        stayOffline = isOn
        dontSendTyping = isOn
        dontReadStories = isOn
    }

    private func store(_ value: Bool, _ key: String, notify: Bool = false) {
        defaults.set(value, forKey: key)
        if notify {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}

/// Keeps IGram's windows out of screen sharing and screenshots while
/// streamer mode is on, including windows opened later.
@MainActor
enum StreamerMode {
    private static var observers: [any NSObjectProtocol] = []

    static func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.didChangeOcclusionStateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated { window.map(apply) }
            })
        }
        observers.append(center.addObserver(forName: ExtraFeatures.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NSApp.windows.forEach(apply) }
        })
        NSApp.windows.forEach(apply)
    }

    private static func apply(_ window: NSWindow) {
        let sharing: NSWindow.SharingType = ExtraFeatures.shared.streamerMode ? .none : .readOnly
        if window.sharingType != sharing { window.sharingType = sharing }
    }
}
