//
//  AnimatedStickerView.swift
//  IGram
//

import Foundation
import Lottie
import SwiftUI
@preconcurrency import TDLibKit

/// Decodes TGS stickers: gzip-compressed Lottie JSON, which tdesktop plays
/// with rlottie and IGram with Lottie.
nonisolated enum TGSDecoder {
    private final class Box {
        let animation: LottieAnimation
        init(_ animation: LottieAnimation) { self.animation = animation }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 200
        return cache
    }()

    static func cached(_ url: URL) -> LottieAnimation? {
        cache.object(forKey: url.path(percentEncoded: false) as NSString)?.animation
    }

    static func load(_ url: URL) async -> LottieAnimation? {
        if let animation = cached(url) { return animation }
        let animation = await Task.detached(priority: .userInitiated) { () -> LottieAnimation? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return decode(data)
        }.value
        if let animation {
            cache.setObject(Box(animation), forKey: url.path(percentEncoded: false) as NSString)
        }
        return animation
    }

    static func decode(_ data: Data) -> LottieAnimation? {
        let json = gunzip(data) ?? data
        guard let dictionary = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        return try? LottieAnimation(dictionary: dictionary)
    }

    /// Strips the gzip wrapper (RFC 1952) and inflates the raw DEFLATE body.
    static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { return nil }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        if flags & 0x08 != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < bytes.count - 8 else { return nil }
        let deflated = Data(bytes[offset..<(bytes.count - 8)])
        // NSData's zlib algorithm is raw DEFLATE, exactly gzip's payload.
        return try? (deflated as NSData).decompressed(using: .zlib) as Data
    }
}

/// A looping TGS sticker, falling back to `placeholder` until it is ready.
struct AnimatedStickerView<Placeholder: View>: View {
    let file: File
    @ViewBuilder var placeholder: Placeholder

    @Environment(TelegramSession.self) private var session
    @State private var animation: LottieAnimation?

    var body: some View {
        let item = session.files.item(for: file)
        ZStack {
            if let animation {
                // Keeps looping while the app is inactive: Lottie's default
                // pause-and-restore rebuilt every sticker's animations when
                // the window came back, so they flashed and jumped.
                LottieView(animation: animation)
                    .resizable()
                    .backgroundBehavior(.continuePlaying)
                    .looping()
            } else {
                placeholder
            }
        }
        .task(id: item.localURL) {
            guard let url = item.localURL else {
                session.files.download(file, priority: .media)
                return
            }
            animation = TGSDecoder.cached(url)
            if animation == nil {
                animation = await TGSDecoder.load(url)
            }
        }
    }
}
