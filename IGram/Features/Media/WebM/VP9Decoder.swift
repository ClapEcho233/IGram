//
//  VP9Decoder.swift
//  IGram
//

import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Decodes VP9 frames with VideoToolbox's decoder for Apple silicon.
nonisolated final class VP9Decoder {
    enum Failure: Error {
        case unavailable
        case format(OSStatus)
        case session(OSStatus)
    }

    private let format: CMVideoFormatDescription
    private let session: VTDecompressionSession

    /// - Parameters:
    ///   - pixelFormat: `32BGRA` for color, a biplanar YUV format to read luma.
    ///   - outputSize: decoded frames are scaled to this size by the decoder.
    init(width: Int, height: Int, profile: Int, pixelFormat: OSType, outputSize: (width: Int, height: Int)) throws {
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
        guard VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9) else { throw Failure.unavailable }

        // VPCodecConfigurationRecord: version 1, profile, level, 8-bit 4:2:0
        // in limited range, BT.601 colors and no initialization data.
        let config = Data([1, 0, 0, 0, UInt8(profile), 10, 8 << 4 | 1 << 1, 6, 6, 6, 0, 0])
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: ["vpcC": config],
            kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_601_4,
            kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_SMPTE_C,
            kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_709_2,
        ]
        var format: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreate(
            allocator: nil,
            codecType: kCMVideoCodecType_VP9,
            width: Int32(width),
            height: Int32(height),
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &format
        )
        guard formatStatus == noErr, let format else { throw Failure.format(formatStatus) }

        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: outputSize.width,
            kCVPixelBufferHeightKey: outputSize.height,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
        ]
        var session: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        )
        guard sessionStatus == noErr, let session else { throw Failure.session(sessionStatus) }
        self.format = format
        self.session = session
    }

    deinit {
        VTDecompressionSessionInvalidate(session)
    }

    /// Decodes one packet synchronously, returning the shown image if any.
    /// Superframes the decoder rejects whole are fed frame by frame.
    func decode(_ packet: Data) -> CVPixelBuffer? {
        let (status, image) = decodeOne(packet)
        if status == noErr { return image }
        let parts = VP9.split(packet)
        guard parts.count > 1 else { return nil }
        var shown: CVPixelBuffer?
        for part in parts {
            if let image = decodeOne(part).image { shown = image }
        }
        return shown
    }

    /// Receives the decoder's output; decoding is synchronous, so no races.
    private final class Output: @unchecked Sendable {
        var image: CVPixelBuffer?
        var status: OSStatus = noErr
    }

    private func decodeOne(_ data: Data) -> (status: OSStatus, image: CVPixelBuffer?) {
        guard let sample = makeSample(data) else { return (-1, nil) }
        let output = Output()
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { status, _, image, _, _ in
            output.status = status
            if let image { output.image = image }
        }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        return (status != noErr ? status : output.status, output.image)
    }

    private func makeSample(_ data: Data) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: data.count, flags: 0, blockBufferOut: &block
        ) == noErr, let block else { return nil }
        let copied = data.withUnsafeBytes { buffer in
            CMBlockBufferReplaceDataBytes(with: buffer.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == noErr else { return nil }
        var sample: CMSampleBuffer?
        var size = data.count
        guard CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 1,
            sampleSizeArray: &size, sampleBufferOut: &sample
        ) == noErr else { return nil }
        return sample
    }
}

/// Plays a WebM video sticker frame by frame: the color stream and, when the
/// sticker is transparent, the alpha stream, merged into premultiplied images.
///
/// Frames are decoded in order on demand rather than cached, since a few
/// seconds of 512×512 frames would take tens of megabytes per sticker.
nonisolated final class WebMStickerDecoder: @unchecked Sendable {
    let demuxer: WebMDemuxer
    let size: (width: Int, height: Int)
    private let color: VP9Decoder
    private let alpha: VP9Decoder?
    private var nextIndex = 0
    private var lock = NSLock()

    var frameCount: Int { demuxer.frames.count }

    init(data: Data, maxPixelSize: Int) throws {
        let demuxer = try WebMDemuxer(data: data)
        guard demuxer.codec == "V_VP9", let first = demuxer.frames.first else { throw WebMDemuxer.Failure.noVideoTrack }
        let width = max(demuxer.width, 1)
        let height = max(demuxer.height, 1)
        let scale = min(1, Double(maxPixelSize) / Double(max(width, height)))
        let size = (width: max(Int((Double(width) * scale).rounded()), 1), height: max(Int((Double(height) * scale).rounded()), 1))
        let profile = VP9.profile(first.data)
        self.demuxer = demuxer
        self.size = size
        color = try VP9Decoder(width: width, height: height, profile: profile, pixelFormat: kCVPixelFormatType_32BGRA, outputSize: size)
        alpha = first.alpha.flatMap { alphaFrame in
            try? VP9Decoder(
                width: width,
                height: height,
                profile: VP9.profile(alphaFrame),
                pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                outputSize: size
            )
        }
    }

    /// The image of frame `index`, decoding the frames before it as needed.
    func image(at index: Int) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard demuxer.frames.indices.contains(index) else { return nil }
        if index < nextIndex {
            // Restart from the closest keyframe at or before the target.
            nextIndex = demuxer.frames[...index].lastIndex(where: \.isKeyframe) ?? 0
        }
        var colorImage: CVPixelBuffer?
        var alphaImage: CVPixelBuffer?
        while nextIndex <= index {
            let frame = demuxer.frames[nextIndex]
            colorImage = color.decode(frame.data)
            if let alpha, let alphaData = frame.alpha {
                alphaImage = alpha.decode(alphaData)
            }
            nextIndex += 1
        }
        guard let colorImage else { return nil }
        return Self.compose(color: colorImage, alpha: alpha == nil ? nil : alphaImage)
    }

    /// Merges a BGRA frame with the luma of the alpha frame.
    static func compose(color: CVPixelBuffer, alpha: CVPixelBuffer?) -> CGImage? {
        let width = CVPixelBufferGetWidth(color)
        let height = CVPixelBufferGetHeight(color)
        CVPixelBufferLockBaseAddress(color, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(color, .readOnly) }
        guard let source = CVPixelBufferGetBaseAddress(color) else { return nil }
        let sourceStride = CVPixelBufferGetBytesPerRow(color)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        var alphaBase: UnsafeMutableRawPointer?
        var alphaStride = 0
        if let alpha {
            CVPixelBufferLockBaseAddress(alpha, .readOnly)
            alphaBase = CVPixelBufferGetBaseAddressOfPlane(alpha, 0)
            alphaStride = CVPixelBufferGetBytesPerRowOfPlane(alpha, 0)
        }
        defer { if let alpha { CVPixelBufferUnlockBaseAddress(alpha, .readOnly) } }
        let alphaWidth = alpha.map { CVPixelBufferGetWidthOfPlane($0, 0) } ?? 0
        let alphaHeight = alpha.map { CVPixelBufferGetHeightOfPlane($0, 0) } ?? 0

        let sourceBytes = source.assumingMemoryBound(to: UInt8.self)
        let alphaBytes = alphaBase?.assumingMemoryBound(to: UInt8.self)
        pixels.withUnsafeMutableBufferPointer { output in
            for y in 0..<height {
                let row = sourceBytes + y * sourceStride
                let alphaRow = alphaBytes.flatMap { y < alphaHeight ? $0 + y * alphaStride : nil }
                for x in 0..<width {
                    let a = alphaRow.map { x < alphaWidth ? Int($0[x]) : 255 } ?? 255
                    let index = (y * width + x) * 4
                    output[index] = UInt8(Int(row[x * 4]) * a / 255)
                    output[index + 1] = UInt8(Int(row[x * 4 + 1]) * a / 255)
                    output[index + 2] = UInt8(Int(row[x * 4 + 2]) * a / 255)
                    output[index + 3] = UInt8(a)
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
