//
//  MediaSizing.swift
//  IGram
//

import CoreGraphics
@preconcurrency import TDLibKit

/// Display sizes for media bubbles, after tdesktop's `CountDesiredMediaSize`.
enum MediaSizing {
    static let maxSize = CGSize(width: 380, height: 420)
    static let minSide: CGFloat = 120

    /// Fits `width`×`height` into `maximum`, never shrinking below `minSide`.
    static func fitted(width: Int, height: Int, maximum: CGSize = maxSize, minSide: CGFloat = minSide) -> CGSize {
        guard width > 0, height > 0 else { return CGSize(width: maximum.width * 0.7, height: maximum.width * 0.7) }
        let w = CGFloat(width)
        let h = CGFloat(height)
        let scale = min(maximum.width / w, maximum.height / h, 1)
        var size = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        if size.width < minSide {
            size = CGSize(width: minSide, height: min((h * minSide / w).rounded(), maximum.height))
        }
        if size.height < minSide / 2 {
            size.height = minSide / 2
        }
        return size
    }

    /// The photo size to download for display: the largest at most `limit` pixels.
    static func displaySize(of photo: Photo, limit: Int = 1280) -> PhotoSize? {
        photo.sizes.last { max($0.width, $0.height) <= limit } ?? photo.sizes.last
    }

    /// The largest size, opened in the viewer.
    static func largestSize(of photo: Photo) -> PhotoSize? {
        photo.sizes.max { $0.width * $0.height < $1.width * $1.height }
    }
}
