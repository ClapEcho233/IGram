//
//  ImagePipeline.swift
//  IGram
//

import Foundation
import ImageIO
import SwiftUI

/// Decodes and downsamples local images off the main thread and caches them.
///
/// Telegram photos are often several megapixels; decoding them at display size
/// keeps memory low the way tdesktop's `Images::Prepare` does.
nonisolated enum ImagePipeline {
    private final class Box {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()

    private static func key(_ url: URL, _ maxPixelSize: Int) -> NSString {
        "\(url.path(percentEncoded: false))#\(maxPixelSize)" as NSString
    }

    static func cached(_ url: URL, maxPixelSize: Int) -> CGImage? {
        cache.object(forKey: key(url, maxPixelSize))?.image
    }

    /// Loads `url` scaled so its longest side is at most `maxPixelSize`.
    static func load(_ url: URL, maxPixelSize: Int) async -> CGImage? {
        if let image = cached(url, maxPixelSize: maxPixelSize) { return image }
        let image = await Task.detached(priority: .userInitiated) {
            decode(url, maxPixelSize: maxPixelSize)
        }.value
        if let image {
            cache.setObject(Box(image), forKey: key(url, maxPixelSize), cost: image.bytesPerRow * image.height)
        }
        return image
    }

    static func decode(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    private static func thumbnail(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Pixel dimensions of the image at `url` without decoding it.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}
