//
//  AttachmentTests.swift
//  IGramTests
//

import Foundation
import Testing
@preconcurrency import TDLibKit
@testable import IGram

@MainActor
struct AttachmentTests {
    private func item(_ name: String, _ kind: PendingAttachment.Kind) -> PendingAttachment {
        PendingAttachment(url: URL(filePath: "/tmp/\(name)"), kind: kind, pixelSize: CGSize(width: 100, height: 80))
    }

    private func isPhoto(_ content: InputMessageContent) -> Bool {
        if case .inputMessagePhoto = content { return true }
        return false
    }

    private func caption(_ content: InputMessageContent) -> String? {
        switch content {
        case .inputMessagePhoto(let value): value.caption?.text
        case .inputMessageVideo(let value): value.caption?.text
        case .inputMessageDocument(let value): value.caption?.text
        default: nil
        }
    }

    @Test func groupsMediaIntoAlbumsOfTen() {
        let photos = (0..<12).map { item("\($0).jpg", .photo) }
        let plan = AttachmentPreparer.plan(photos, asFiles: false, caption: nil)
        #expect(plan.map(\.count) == [10, 2])
        #expect(plan.flatMap { $0 }.allSatisfy(isPhoto))
    }

    @Test func sendsOtherFilesSeparately() {
        let plan = AttachmentPreparer.plan(
            [item("a.jpg", .photo), item("b.pdf", .file), item("c.mov", .video(duration: 3))],
            asFiles: false,
            caption: nil
        )
        #expect(plan.map(\.count) == [2, 1])
    }

    @Test func asFilesSendsDocuments() {
        let plan = AttachmentPreparer.plan([item("a.jpg", .photo), item("b.jpg", .photo)], asFiles: true, caption: nil)
        #expect(plan.map(\.count) == [1, 1])
        #expect(plan.flatMap { $0 }.allSatisfy { !isPhoto($0) })
    }

    @Test func captionGoesOnFirstMessageOnly() {
        let plan = AttachmentPreparer.plan(
            [item("a.jpg", .photo), item("b.jpg", .photo)],
            asFiles: false,
            caption: FormattedText(entities: [], text: "Hello")
        )
        let captions = plan.flatMap { $0 }.map(caption)
        #expect(captions == ["Hello", nil])
    }

    @Test func classifiesByExtension() async throws {
        let directory = try AttachmentPreparer.uploadsDirectory()
        let text = directory.appending(path: "notes.txt")
        try Data("hi".utf8).write(to: text)
        #expect(await AttachmentPreparer.classify(text).kind == .file)
    }
}
