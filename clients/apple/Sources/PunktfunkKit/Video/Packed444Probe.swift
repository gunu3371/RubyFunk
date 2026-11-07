import CoreMedia
import CoreVideo
import Foundation
import Metal
import VideoToolbox

enum Packed444Probe {
    /// Probe the exact carrier dimensions; session creation doesn't prove sustained throughput.
    static func capabilities(width: Int, height: Int, fps: Int) -> [UInt8] {
        let disabled = [UInt8](repeating: 0, count: 18)
        guard let g = Packed444Layout(width: width, height: height), (1...240).contains(fps),
              let device = MTLCreateSystemDefaultDevice(),
              (try? Packed444Restorer(device: device)) != nil else { return disabled }
        var modes: UInt8 = 0
        if let format = av1Format(width: g.codedWidth, height: g.codedHeight), accepts(format) {
            modes |= 4
        }
        if let format = hevcFormat(width: g.codedWidth, height: g.codedHeight), accepts(format) {
            modes |= 1
        }
        guard modes != 0 else { return disabled }
        func le(_ value: UInt64, _ count: Int) -> [UInt8] {
            (0..<count).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
        }
        return [1, modes] + le(UInt64(g.codedWidth), 4) + le(UInt64(g.codedHeight), 4)
            + le(UInt64(g.codedWidth) * UInt64(g.codedHeight) * UInt64(fps), 8)
    }

    private static func accepts(_ format: CMVideoFormatDescription) -> Bool {
        guard VTIsHardwareDecodeSupported(CMFormatDescriptionGetMediaSubType(format)) else { return false }
        let spec = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true] as CFDictionary
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: nil, formatDescription: format, decoderSpecification: spec,
            imageBufferAttributes: attrs as CFDictionary, outputCallback: nil,
            decompressionSessionOut: &session)
        if let session { VTDecompressionSessionInvalidate(session) }
        return status == noErr && session != nil
    }

    /// AV1 reduced still-picture sequence header, Main 8-bit 4:2:0, full-range BT.709.
    static func av1Format(width: Int, height: Int) -> CMVideoFormatDescription? {
        var bits: [UInt8] = []
        func put(_ value: Int, _ count: Int) {
            for shift in (0..<count).reversed() { bits.append(UInt8((value >> shift) & 1)) }
        }
        put(0, 3); put(1, 1); put(1, 1); put(19, 5)
        let wb = max(1, Int.bitWidth - (width - 1).leadingZeroBitCount)
        let hb = max(1, Int.bitWidth - (height - 1).leadingZeroBitCount)
        put(wb - 1, 4); put(hb - 1, 4); put(width - 1, wb); put(height - 1, hb)
        put(0, 3) // superblocks, filter intra, intra edge
        put(0, 3) // super-resolution, CDEF, restoration
        put(0, 1); put(0, 1); put(1, 1) // depth, monochrome, colour description
        put(1, 8); put(1, 8); put(1, 8)
        put(1, 1); put(0, 2); put(0, 1); put(0, 1) // full range, siting, UV delta, grain
        put(1, 1)
        while bits.count % 8 != 0 { put(0, 1) }
        let payload = stride(from: 0, to: bits.count, by: 8).map { at in
            bits[at..<at + 8].reduce(UInt8(0)) { ($0 << 1) | $1 }
        }
        let config = Data([0x81, 19, 0x0c, 0, 0x0a, UInt8(payload.count)] + payload)
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: ["av1C": config],
        ]
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreate(
            allocator: nil, codecType: kCMVideoCodecType_AV1, width: Int32(width), height: Int32(height),
            extensions: extensions as CFDictionary, formatDescriptionOut: &format) == noErr else { return nil }
        return format
    }

    private final class EncodedFormat {
        var format: CMVideoFormatDescription?
    }

    private static func hevcFormat(width: Int, height: Int) -> CMVideoFormatDescription? {
        let result = EncodedFormat()
        var session: VTCompressionSession?
        let callback: VTCompressionOutputCallback = { context, _, status, _, sample in
            guard status == noErr, let context, let sample else { return }
            Unmanaged<EncodedFormat>.fromOpaque(context).takeUnretainedValue().format =
                CMSampleBufferGetFormatDescription(sample)
        }
        guard VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: callback,
            refcon: Unmanaged.passUnretained(result).toOpaque(), compressionSessionOut: &session) == noErr,
              let session else { return nil }
        defer { VTCompressionSessionInvalidate(session) }
        _ = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        var image: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                  [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                                  &image) == kCVReturnSuccess, let image else { return nil }
        guard CVPixelBufferLockBaseAddress(image, []) == kCVReturnSuccess else { return nil }
        if let base = CVPixelBufferGetBaseAddress(image) {
            memset(base, 0, CVPixelBufferGetBytesPerRow(image) * height)
        }
        CVPixelBufferUnlockBaseAddress(image, [])
        guard VTCompressionSessionEncodeFrame(session, imageBuffer: image, presentationTimeStamp: .zero,
            duration: CMTime(value: 1, timescale: 60), frameProperties: nil, sourceFrameRefcon: nil,
            infoFlagsOut: nil) == noErr else { return nil }
        _ = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        return result.format
    }
}
