//
//  AlbumView.swift
//  IGram
//

import SwiftUI
@preconcurrency import TDLibKit

/// Several photos and videos sent together, laid out in rows of up to two
/// tiles, a simplified version of tdesktop's `Ui::LayoutMediaGroup`.
struct AlbumView: View {
    let messages: [ChatMessage]
    var width: CGFloat = MediaSizing.maxSize.width

    private let spacing: CGFloat = 2

    var body: some View {
        let rows = Self.rows(for: messages.count)
        VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let tileWidth = (width - spacing * CGFloat(row.count - 1)) / CGFloat(row.count)
                let height = rowHeight(row, tileWidth: tileWidth)
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { index in
                        VisualMediaView(content: messages[index].content, size: CGSize(width: tileWidth, height: height))
                    }
                }
            }
        }
        .frame(width: width)
    }

    private func rowHeight(_ row: [Int], tileWidth: CGFloat) -> CGFloat {
        let heights = row.map { index -> CGFloat in
            let media = VisualMedia(content: messages[index].content)
            guard media.width > 0 else { return tileWidth }
            return tileWidth * CGFloat(media.height) / CGFloat(media.width)
        }
        let average = heights.reduce(0, +) / CGFloat(max(heights.count, 1))
        return min(max(average, 90), 280)
    }

    /// Indices grouped into rows: a single tile on the first row for odd counts.
    static func rows(for count: Int) -> [[Int]] {
        guard count > 0 else { return [] }
        var rows: [[Int]] = []
        var index = 0
        if count % 2 == 1 {
            rows.append([0])
            index = 1
        }
        while index < count {
            rows.append(Array(index..<min(index + 2, count)))
            index += 2
        }
        return rows
    }
}
