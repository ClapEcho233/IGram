//
//  InlineBotResultsTests.swift
//  IGramTests
//

import Foundation
import Testing
@preconcurrency import TDLibKit
@testable import IGram

struct InlineBotResultsTests {
    @Test func parsesLeadingBotQuery() {
        #expect(InlineQuery.parse("@gif cats") == InlineQuery(botUsername: "gif", query: "cats"))
        #expect(InlineQuery.parse("@wiki ") == InlineQuery(botUsername: "wiki", query: ""))
        #expect(InlineQuery.parse("@imdb_bot star wars") == InlineQuery(botUsername: "imdb_bot", query: "star wars"))
    }

    @Test func rejectsNonInlineSyntax() {
        #expect(InlineQuery.parse("@gif") == nil)
        #expect(InlineQuery.parse("hello @gif cats") == nil)
        #expect(InlineQuery.parse("@ab cats") == nil)
        #expect(InlineQuery.parse("@1bot cats") == nil)
        #expect(InlineQuery.parse("@bad-name cats") == nil)
        #expect(InlineQuery.parse("") == nil)
    }

    @Test func selectsGridOnlyForVisualTilesWithoutText() {
        let article = InlineQueryResult.inlineQueryResultArticle(InlineQueryResultArticle(
            description: "Summary", id: "1", thumbnail: nil, title: "Swift", url: "https://swift.org"
        ))
        let barePhoto = InlineQueryResult.inlineQueryResultPhoto(InlineQueryResultPhoto(
            description: "", id: "2", photo: Photo(hasStickers: false, minithumbnail: nil, sizes: []), title: ""
        ))
        let titledPhoto = InlineQueryResult.inlineQueryResultPhoto(InlineQueryResultPhoto(
            description: "Caption", id: "3", photo: Photo(hasStickers: false, minithumbnail: nil, sizes: []), title: "Sunset"
        ))

        #expect(!InlineResultsModel.isGridLayout([]))
        #expect(InlineResultsModel.isGridLayout([barePhoto]))
        #expect(!InlineResultsModel.isGridLayout([titledPhoto]))
        #expect(!InlineResultsModel.isGridLayout([barePhoto, article]))
        #expect(article.resultId == "1")
        #expect(barePhoto.resultId == "2")
    }
}
