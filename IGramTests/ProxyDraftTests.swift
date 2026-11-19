//
//  ProxyDraftTests.swift
//  IGramTests
//

import Foundation
import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct ProxyDraftTests {
    @Test func parsesMTProtoLinks() throws {
        let draft = try #require(ProxyDraft(url: URL(string: "tg://proxy?server=1.2.3.4&port=443&secret=abcd")!))
        #expect(draft.kind == .mtproto)
        #expect(draft.proxy == Proxy(port: 443, server: "1.2.3.4", type: .proxyTypeMtproto(ProxyTypeMtproto(secret: "abcd"))))
    }

    @Test func parsesSocksLinks() throws {
        let draft = try #require(ProxyDraft(url: URL(string: "https://t.me/socks?server=proxy.example&port=1080&user=u&pass=p")!))
        #expect(draft.kind == .socks5)
        #expect(draft.username == "u" && draft.password == "p")
    }

    @Test func rejectsOtherLinks() {
        #expect(ProxyDraft(url: URL(string: "https://t.me/durov")!) == nil)
        #expect(ProxyDraft(url: URL(string: "tg://proxy?server=x")!) == nil)
    }

    @Test func validatesPort() {
        var draft = ProxyDraft()
        draft.server = "a"
        draft.port = "70000"
        #expect(draft.proxy == nil)
        draft.port = "8080"
        #expect(draft.proxy != nil)
    }
}
