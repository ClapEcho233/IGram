//
//  ProxySettingsView.swift
//  IGram
//

import OSLog
import SwiftUI
@preconcurrency import TDLibKit

/// Proxy servers, after tdesktop's `ProxiesBox`.
struct ProxySettingsView: View {
    @Environment(TelegramSession.self) private var session
    @State private var proxies: [AddedProxy] = []
    @State private var pings: [Int: String] = [:]
    @State private var isAdding = false

    var body: some View {
        Form {
            Section {
                Toggle("Use proxy", isOn: Binding(
                    get: { proxies.contains(where: \.isEnabled) },
                    set: { enabled in
                        Task {
                            if enabled, let first = proxies.first {
                                _ = try? await session.api.enableProxy(proxyId: first.id)
                            } else {
                                _ = try? await session.api.disableProxy()
                            }
                            await reload()
                        }
                    }
                ))
                .disabled(proxies.isEmpty)
            } footer: {
                Text(connectionText).foregroundStyle(.secondary)
            }
            Section("Proxies") {
                ForEach(proxies, id: \.id) { proxy in
                    HStack {
                        Image(systemName: proxy.isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(proxy.isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        VStack(alignment: .leading) {
                            Text("\(proxy.proxy.server):\(proxy.proxy.port)")
                            Text("\(Self.typeName(proxy.proxy.type)) · \(pings[proxy.id] ?? String(localized: "checking…"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task {
                                _ = try? await session.api.removeProxy(proxyId: proxy.id)
                                await reload()
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove proxy")
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        Task {
                            _ = try? await session.api.enableProxy(proxyId: proxy.id)
                            await reload()
                        }
                    }
                }
                Button("Add Proxy…", systemImage: "plus") { isAdding = true }
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
        .sheet(isPresented: $isAdding, onDismiss: { Task { await reload() } }) {
            AddProxySheet()
        }
    }

    private var connectionText: String {
        switch session.connectionState {
        case .connectionStateReady: String(localized: "Connected.")
        case .connectionStateConnectingToProxy: String(localized: "Connecting to proxy…")
        case .connectionStateWaitingForNetwork: String(localized: "Waiting for network…")
        default: String(localized: "Connecting…")
        }
    }

    private func reload() async {
        proxies = (try? await session.api.getProxies())?.proxies ?? []
        for proxy in proxies {
            let api = session.api
            Task {
                do {
                    let seconds = try await api.pingProxy(proxy: proxy.proxy).seconds
                    pings[proxy.id] = String(localized: "\(Int(seconds * 1000)) ms")
                } catch {
                    pings[proxy.id] = String(localized: "unavailable")
                }
            }
        }
    }

    static func typeName(_ type: ProxyType) -> String {
        switch type {
        case .proxyTypeSocks5: "SOCKS5"
        case .proxyTypeHttp: "HTTP"
        case .proxyTypeMtproto: "MTProto"
        case .proxyTypeWeb: "Web"
        }
    }
}

/// Fields of a proxy being added, also filled from proxy links.
struct ProxyDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case socks5, http, mtproto
        var id: String { rawValue }
    }

    var kind: Kind = .socks5
    var server = ""
    var port = ""
    var username = ""
    var password = ""
    var secret = ""

    var proxy: Proxy? {
        guard !server.isEmpty, let port = Int(port), (1...65_535).contains(port) else { return nil }
        let type: ProxyType = switch kind {
        case .socks5: .proxyTypeSocks5(ProxyTypeSocks5(password: password, username: username))
        case .http: .proxyTypeHttp(ProxyTypeHttp(httpOnly: false, password: password, username: username))
        case .mtproto: .proxyTypeMtproto(ProxyTypeMtproto(secret: secret))
        }
        return Proxy(port: port, server: server, type: type)
    }

    /// Parses `tg://proxy?server=…&port=…&secret=…`, `tg://socks?…` and their t.me forms.
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path: String
        if url.scheme == "tg" {
            path = url.host() ?? ""
        } else if ["t.me", "telegram.me"].contains(url.host()?.lowercased() ?? "") {
            path = String(url.path(percentEncoded: false).dropFirst())
        } else {
            return nil
        }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        switch path {
        case "proxy": kind = .mtproto
        case "socks": kind = .socks5
        default: return nil
        }
        server = query["server"] ?? ""
        port = query["port"] ?? ""
        username = query["user"] ?? ""
        password = query["pass"] ?? ""
        secret = query["secret"] ?? ""
        guard !server.isEmpty, !port.isEmpty else { return nil }
    }

    init() {}
}

struct AddProxySheet: View {
    @State var draft = ProxyDraft()

    @Environment(TelegramSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: String(localized: "Add Proxy"), errorMessage: errorMessage) {
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.proxy == nil)
            }
            Form {
                Picker("Type", selection: $draft.kind) {
                    Text("SOCKS5").tag(ProxyDraft.Kind.socks5)
                    Text("HTTP").tag(ProxyDraft.Kind.http)
                    Text("MTProto").tag(ProxyDraft.Kind.mtproto)
                }
                .pickerStyle(.segmented)
                TextField("Server", text: $draft.server)
                TextField("Port", text: $draft.port)
                if draft.kind == .mtproto {
                    TextField("Secret", text: $draft.secret)
                } else {
                    TextField("Username (optional)", text: $draft.username)
                    SecureField("Password (optional)", text: $draft.password)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 340)
    }

    private func save() {
        guard let proxy = draft.proxy else { return }
        Task {
            do {
                _ = try await session.api.addProxy(comment: "", enable: true, proxy: proxy)
                dismiss()
            } catch {
                errorMessage = error.telegramMessage
            }
        }
    }
}
