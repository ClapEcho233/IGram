//
//  MediaSizingTests.swift
//  IGramTests
//

import CoreGraphics
import Testing
@testable import IGram

@MainActor
struct MediaSizingTests {
    @Test func scalesDownLargeLandscape() {
        let size = MediaSizing.fitted(width: 1920, height: 1080)
        #expect(size.width == 380)
        #expect(size.height == 214)
    }

    @Test func scalesDownTallPortrait() {
        let size = MediaSizing.fitted(width: 1080, height: 1920)
        #expect(size.height == 420)
        #expect(size.width == 236)
    }

    @Test func keepsSmallImagesAtNaturalSizeAboveMinimum() {
        #expect(MediaSizing.fitted(width: 200, height: 150) == CGSize(width: 200, height: 150))
    }

    @Test func enforcesMinimumWidth() {
        let size = MediaSizing.fitted(width: 50, height: 400)
        #expect(size.width == MediaSizing.minSide)
        #expect(size.height == 420)
    }

    @Test func unknownDimensionsGetSquare() {
        let size = MediaSizing.fitted(width: 0, height: 0)
        #expect(size.width == size.height)
    }

    @Test func albumRows() {
        #expect(AlbumView.rows(for: 1) == [[0]])
        #expect(AlbumView.rows(for: 2) == [[0, 1]])
        #expect(AlbumView.rows(for: 3) == [[0], [1, 2]])
        #expect(AlbumView.rows(for: 4) == [[0, 1], [2, 3]])
        #expect(AlbumView.rows(for: 0).isEmpty)
    }
}
