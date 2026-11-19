//
//  WebAppSheet.swift
//  IGram
//

import AppKit
import Observation
import OSLog
import SwiftUI
@preconcurrency import TDLibKit
@preconcurrency import WebKit

/// Drives an embedded Telegram Mini App (Web App) inside a native sheet.
@Observable
final class WebAppModel {
    let request: WebAppRequest

    private(set) var launchedURL: URL?
    private(set) var requireSameOrigin = false
    private(set) var launchId: TdInt64?
    private(set) var isLaunching = true
    private(set) var isLoadingPage = false
    private(set) var loadError: String?
    private(set) var isExpanded = false
    private(set) var backButtonVisible = false
    private(set) var settingsButtonVisible = false
    private(set) var mainButton = WebAppButtonState()
    private(set) var secondaryButton = WebAppButtonState()
    private(set) var headerColorRGB: Int?
    private(set) var backgroundColorRGB: Int?
    private(set) var bottomBarColorRGB: Int?
    private(set) var needsClosingConfirmation = false
    var isConfirmingClose = false
    var activePopup: WebAppPopup?
    var isConfirmingWriteAccess = false
    var isConfirmingPhone = false

    @ObservationIgnored var onDismiss: (() -> Void)?
    @ObservationIgnored var onOpenTelegramURL: ((URL) -> Void)?
    @ObservationIgnored var onSwitchInlineQuery: ((String, String) -> Void)?
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private var currentTheme: WebAppTheme = .light
    @ObservationIgnored private var didCloseWithTDLib = false
    @ObservationIgnored private var session: TelegramSession?

    init(request: WebAppRequest) {
        self.request = request
    }

    var currentHost: String? {
        launchedURL?.host() ?? request.launch.fallbackURL?.host()
    }

    var resolvedTheme: WebAppTheme { currentTheme }

    func launch(session: TelegramSession, isDark: Bool) async {
        self.session = session
        currentTheme = .current(isDark: isDark)
        applyBotDefaultColors(session: session, isDark: isDark)
        isLaunching = true
        loadError = nil

        let parameters = WebAppOpenParameters(
            applicationName: "igram",
            mode: .webAppOpenModeFullSize,
            theme: currentTheme.tdlibParameters
        )
        do {
            switch request.launch {
            case .chat(let botUserId, let chatId, let url, let topicId):
                let info = try await session.api.openWebApp(
                    botUserId: botUserId,
                    chatId: chatId,
                    parameters: parameters,
                    replyTo: nil,
                    topicId: topicId,
                    url: url
                )
                launchId = info.launchId
                requireSameOrigin = info.url.requireSameOrigin
                launchedURL = URL(string: info.url.url)
            case .simple(let botUserId, let url, _):
                let result = try await session.api.getWebAppUrl(
                    botUserId: botUserId,
                    parameters: parameters,
                    url: url
                )
                requireSameOrigin = result.requireSameOrigin
                launchedURL = URL(string: result.url)
            case .mainApp(let botUserId, let chatId, let startParameter):
                let result = try await session.api.getMainWebApp(
                    botUserId: botUserId,
                    chatId: chatId,
                    parameters: parameters,
                    startParameter: startParameter
                )
                isExpanded = result.mode == .webAppOpenModeFullScreen
                requireSameOrigin = result.url.requireSameOrigin
                launchedURL = URL(string: result.url.url)
            }
            if launchedURL == nil {
                loadError = String(localized: "Couldn't open this Web App.")
            }
        } catch {
            loadError = error.telegramMessage
            Log.ui.error("Web App launch failed: \(error.telegramMessage, privacy: .public)")
        }
        isLaunching = false
    }

    func updateColorScheme(isDark: Bool) {
        currentTheme = .current(isDark: isDark)
        sendTheme()
    }

    func requestClose() {
        if needsClosingConfirmation {
            isConfirmingClose = true
        } else {
            closeNow()
        }
    }

    func closeNow() {
        notifyTDLibClosed()
        onDismiss?()
    }

    func notifyTDLibClosed() {
        guard !didCloseWithTDLib, let launchId, let api = session?.api else { return }
        didCloseWithTDLib = true
        Task { _ = try? await api.closeWebApp(webAppLaunchId: launchId) }
    }

    func reload() {
        loadError = nil
        if let webView {
            webView.reload()
        }
    }

    func setLoading(_ loading: Bool, error: String? = nil) {
        isLoadingPage = loading
        if let error { loadError = error }
    }

    // MARK: - Outbound events (host → Web App)

    func pressBackButton() {
        sendEvent("back_button_pressed")
    }

    func pressSettingsButton() {
        sendEvent("settings_button_pressed")
    }

    func pressMainButton() {
        guard mainButton.isActive, !mainButton.isProgressVisible else { return }
        sendEvent("main_button_pressed")
    }

    func pressSecondaryButton() {
        guard secondaryButton.isActive, !secondaryButton.isProgressVisible else { return }
        sendEvent("secondary_button_pressed")
    }

    func sendTheme() {
        sendEvent("theme_changed", payload: ["theme_params": currentTheme.jsDictionary])
    }

    func sendViewport(height: CGFloat? = nil) {
        let resolvedHeight = Int(height ?? webView?.bounds.height ?? (isExpanded ? 680 : 560))
        sendEvent("viewport_changed", payload: [
            "height": max(resolvedHeight, 200),
            "is_state_stable": true,
            "is_expanded": isExpanded,
        ])
    }

    func finishPopup(buttonId: String?) {
        activePopup = nil
        if let buttonId {
            sendEvent("popup_closed", payload: ["button_id": buttonId])
        } else {
            sendEvent("popup_closed", payload: [:])
        }
    }

    func respondWriteAccess(allowed: Bool) {
        isConfirmingWriteAccess = false
        guard allowed, let api = session?.api else {
            sendEvent("write_access_requested", payload: ["status": "cancelled"])
            return
        }
        let botId = request.launch.botUserId
        Task {
            do {
                _ = try await api.allowBotToSendMessages(botUserId: botId)
                sendEvent("write_access_requested", payload: ["status": "allowed"])
            } catch {
                sendEvent("write_access_requested", payload: ["status": "cancelled"])
            }
        }
    }

    func respondPhone(allowed: Bool) {
        isConfirmingPhone = false
        guard allowed, let api = session?.api else {
            sendEvent("phone_requested", payload: ["status": "cancelled"])
            return
        }
        let botId = request.launch.botUserId
        Task {
            do {
                _ = try await api.sharePhoneNumber(userId: botId)
                sendEvent("phone_requested", payload: ["status": "sent"])
            } catch {
                sendEvent("phone_requested", payload: ["status": "cancelled"])
            }
        }
    }

    // MARK: - Inbound events (Web App → host)

    func handleBridgeMessage(type: String, rawData: Any?, frameURL: URL?) {
        if requireSameOrigin, !WebAppBridge.sameOrigin(frameURL, launchedURL) {
            Log.ui.warning("Ignored Web App event from foreign origin")
            return
        }
        let event = WebAppEvent.parse(type: type, rawData: rawData)
        switch event {
        case .ready:
            sendTheme()
            sendViewport()
        case .close:
            closeNow()
        case .expand:
            isExpanded = true
            sendViewport()
        case .requestTheme:
            sendTheme()
        case .requestViewport:
            sendViewport()
        case .setupMainButton(let state):
            mainButton = state
        case .setupSecondaryButton(let state):
            secondaryButton = state
        case .setupBackButton(let visible):
            backButtonVisible = visible
        case .setupSettingsButton(let visible):
            settingsButtonVisible = visible
        case .setHeaderColor(let value):
            headerColorRGB = currentTheme.resolve(value)
        case .setBackgroundColor(let value):
            backgroundColorRGB = currentTheme.resolve(value)
        case .setBottomBarColor(let value):
            bottomBarColorRGB = currentTheme.resolve(value)
        case .setupClosingBehavior(let needConfirmation):
            needsClosingConfirmation = needConfirmation
        case .openLink(let string):
            if let url = WebAppBridge.safeExternalURL(from: string) {
                NSWorkspace.shared.open(url)
            }
        case .openTelegramLink(let pathFull):
            if let url = WebAppBridge.telegramURL(from: pathFull) {
                closeNow()
                onOpenTelegramURL?(url)
            }
        case .sendData(let data):
            guard case .simple(let botUserId, _, let buttonText) = request.launch,
                  let api = session?.api else { return }
            Task {
                _ = try? await api.sendWebAppData(
                    botUserId: botUserId,
                    buttonText: buttonText ?? request.title,
                    data: data
                )
                closeNow()
            }
        case .invokeCustomMethod(let requestId, let method, let paramsJSON):
            guard let api = session?.api else { return }
            let botId = request.launch.botUserId
            Task {
                do {
                    let result = try await api.sendWebAppCustomRequest(
                        botUserId: botId,
                        method: method,
                        parameters: paramsJSON
                    )
                    if let parsed = result.result.data(using: .utf8).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) {
                        sendEvent("custom_method_invoked", payload: ["req_id": requestId, "result": parsed])
                    } else {
                        sendEvent("custom_method_invoked", payload: ["req_id": requestId, "result": result.result])
                    }
                } catch {
                    sendEvent("custom_method_invoked", payload: ["req_id": requestId, "error": error.telegramMessage])
                }
            }
        case .openPopup(let popup):
            activePopup = popup
        case .switchInlineQuery(let query):
            guard let username = session?.peers.user(request.launch.botUserId).user?.username else { return }
            closeNow()
            onSwitchInlineQuery?(username, query)
        case .requestWriteAccess:
            isConfirmingWriteAccess = true
        case .requestPhone:
            isConfirmingPhone = true
        case .hapticFeedback:
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        case .unknown:
            break
        }
    }

    private func sendEvent(_ type: String, payload: [String: Any]? = nil) {
        guard let script = WebAppBridge.receiveEventScript(type: type, payload: payload) else { return }
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private func applyBotDefaultColors(session: TelegramSession, isDark: Bool) {
        guard let info = session.peers.user(request.launch.botUserId).fullInfo?.botInfo else { return }
        let bg = isDark ? info.webAppBackgroundDarkColor : info.webAppBackgroundLightColor
        let header = isDark ? info.webAppHeaderDarkColor : info.webAppHeaderLightColor
        if bg >= 0 { backgroundColorRGB = bg }
        if header >= 0 { headerColorRGB = header }
    }
}

/// Native macOS sheet hosting a Telegram Mini App in `WKWebView`.
struct WebAppSheet: View {
    let request: WebAppRequest

    @Environment(TelegramSession.self) private var session
    @Environment(MainModel.self) private var main
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var model: WebAppModel

    init(request: WebAppRequest) {
        self.request = request
        _model = State(initialValue: WebAppModel(request: request))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
            if model.mainButton.isVisible || model.secondaryButton.isVisible {
                Divider()
                bottomButtonBar
            }
        }
        .frame(
            width: model.isExpanded ? 540 : 440,
            height: model.isExpanded ? 740 : 620
        )
        .background(Color(rgb: model.backgroundColorRGB ?? model.resolvedTheme.background))
        .animation(.snappy(duration: 0.2), value: model.isExpanded)
        .task {
            model.onDismiss = { dismiss() }
            model.onOpenTelegramURL = { url in
                _ = LinkRouter(session: session, main: main).handle(url)
            }
            model.onSwitchInlineQuery = { username, query in
                if let chatId = main.selectedChatId {
                    main.pendingComposerText = MainModel.ComposerDraft(chatId: chatId, text: "@\(username) \(query)")
                }
            }
            await model.launch(session: session, isDark: colorScheme == .dark)
        }
        .onChange(of: colorScheme) { _, scheme in
            model.updateColorScheme(isDark: scheme == .dark)
        }
        .onDisappear {
            model.notifyTDLibClosed()
        }
        .interactiveDismissDisabled(model.needsClosingConfirmation)
        .confirmationDialog(
            "Close \(request.title)?",
            isPresented: $model.isConfirmingClose,
            titleVisibility: .visible
        ) {
            Button("Close Anyway", role: .destructive) { model.closeNow() }
        } message: {
            Text("Changes that you made may not be saved.")
        }
        .confirmationDialog(
            "Allow \(request.title) to message you?",
            isPresented: $model.isConfirmingWriteAccess,
            titleVisibility: .visible
        ) {
            Button("Allow") { model.respondWriteAccess(allowed: true) }
            Button("Cancel", role: .cancel) { model.respondWriteAccess(allowed: false) }
        } message: {
            Text("This bot wants permission to send you messages.")
        }
        .confirmationDialog(
            "Share your phone number with \(request.title)?",
            isPresented: $model.isConfirmingPhone,
            titleVisibility: .visible
        ) {
            Button("Share Phone Number") { model.respondPhone(allowed: true) }
            Button("Cancel", role: .cancel) { model.respondPhone(allowed: false) }
        }
        .alert(
            model.activePopup?.title.isEmpty == false ? (model.activePopup?.title ?? "") : request.title,
            isPresented: Binding(get: { model.activePopup != nil }, set: { if !$0 { model.finishPopup(buttonId: nil) } }),
            presenting: model.activePopup
        ) { popup in
            if popup.buttons.isEmpty {
                Button("OK") { model.finishPopup(buttonId: nil) }
            } else {
                ForEach(popup.buttons) { button in
                    Button(popupButtonTitle(button), role: popupButtonRole(button)) {
                        model.finishPopup(buttonId: button.id)
                    }
                }
            }
        } message: { popup in
            Text(popup.message)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            if model.backButtonVisible {
                Button {
                    model.pressBackButton()
                } label: {
                    Image(systemName: "chevron.backward")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Back")
            } else {
                Button {
                    model.requestClose()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(request.title)
                    .font(.headline)
                    .lineLimit(1)
                if let host = model.currentHost {
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if model.isLaunching || model.isLoadingPage {
                ProgressView()
                    .controlSize(.small)
            }

            if model.settingsButtonVisible {
                Button {
                    model.pressSettingsButton()
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }

            Menu {
                Button("Reload", systemImage: "arrow.clockwise") { model.reload() }
                    .disabled(model.launchedURL == nil)
                if let url = model.launchedURL ?? request.launch.fallbackURL {
                    Button("Open in Browser", systemImage: "safari") {
                        NSWorkspace.shared.open(url)
                    }
                    Button("Copy Link", systemImage: "link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        main.showToast(String(localized: "Link copied"))
                    }
                }
                Divider()
                Button("Close", systemImage: "xmark") { model.requestClose() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(model.headerColorRGB.map { AnyShapeStyle(Color(rgb: $0)) } ?? AnyShapeStyle(.bar))
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if let url = model.launchedURL {
                WebAppWebView(url: url, model: model)
            } else if model.isLaunching {
                ProgressView("Opening Web App…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("Couldn't Open Web App", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(model.loadError ?? String(localized: "The Web App couldn't be loaded."))
                } actions: {
                    if let fallback = request.launch.fallbackURL {
                        Button("Open in Browser") { NSWorkspace.shared.open(fallback) }
                    }
                    Button("Close") { model.closeNow() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomButtonBar: some View {
        HStack(spacing: 8) {
            if model.secondaryButton.isVisible {
                miniAppButton(model.secondaryButton, defaultColor: model.resolvedTheme.secondaryBackground, defaultText: model.resolvedTheme.button) {
                    model.pressSecondaryButton()
                }
            }
            if model.mainButton.isVisible {
                miniAppButton(model.mainButton, defaultColor: model.resolvedTheme.button, defaultText: model.resolvedTheme.buttonText) {
                    model.pressMainButton()
                }
            }
        }
        .padding(12)
        .background(Color(rgb: model.bottomBarColorRGB ?? model.resolvedTheme.bottomBarBackground))
    }

    private func miniAppButton(
        _ state: WebAppButtonState,
        defaultColor: Int,
        defaultText: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if state.isProgressVisible {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(state.text)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color(rgb: state.textColor ?? defaultText))
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(Color(rgb: state.color ?? defaultColor), in: .rect(cornerRadius: 8))
            .opacity(state.isActive ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!state.isActive || state.isProgressVisible)
    }

    private func popupButtonTitle(_ button: WebAppPopup.Button) -> String {
        if !button.text.isEmpty { return button.text }
        switch button.kind {
        case .ok: return String(localized: "OK")
        case .close: return String(localized: "Close")
        case .cancel: return String(localized: "Cancel")
        case .default, .destructive: return String(localized: "OK")
        }
    }

    private func popupButtonRole(_ button: WebAppPopup.Button) -> ButtonRole? {
        switch button.kind {
        case .cancel: .cancel
        case .destructive: .destructive
        case .default, .ok, .close: nil
        }
    }
}

/// Bridges `WKWebView` into SwiftUI and installs `TelegramWebviewProxy`.
private struct WebAppWebView: NSViewRepresentable {
    let url: URL
    let model: WebAppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let script = WKUserScript(source: WebAppBridge.proxyScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(script)
        controller.add(context.coordinator, name: WebAppBridge.messageHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        model.webView = webView
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: WebAppBridge.messageHandlerName)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        weak var model: WebAppModel?
        var loadedURL: URL?

        init(model: WebAppModel) {
            self.model = model
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == WebAppBridge.messageHandlerName,
                  let body = message.body as? [String: Any],
                  let type = body["eventType"] as? String else { return }
            let rawData = body["eventData"]
            let frameURL = message.frameInfo.request.url
            model?.handleBridgeMessage(type: type, rawData: rawData, frameURL: frameURL)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model?.setLoading(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model?.setLoading(false)
            model?.sendTheme()
            model?.sendViewport(height: webView.bounds.height)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            model?.setLoading(false, error: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Swift.Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
            model?.setLoading(false, error: error.localizedDescription)
        }

        /// Opens `target="_blank"` links in the user's default browser.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url, WebAppBridge.safeExternalURL(from: url.absoluteString) != nil {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}
