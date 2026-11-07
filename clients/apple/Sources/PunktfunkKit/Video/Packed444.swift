import CoreVideo
import Foundation
import Metal

public struct Packed444Layout: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let codedWidth: Int
    public let codedHeight: Int

    public init?(width: Int, height: Int) {
        guard (1...16384).contains(width), (1...8192).contains(height) else { return nil }
        self.width = width
        self.height = height
        codedWidth = (width + 63) / 64 * 64
        codedHeight = (height + 7) / 8 * 16
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count == 17, bytes[0] == 1 else { return nil }
        func word(_ at: Int) -> Int {
            (0..<4).reduce(0) { $0 | (Int(bytes[at + $1]) << (8 * $1)) }
        }
        self.init(width: word(1), height: word(5))
        guard codedWidth == word(9), codedHeight == word(13) else { return nil }
    }

    public var bytes: [UInt8] {
        [1] + [width, height, codedWidth, codedHeight].flatMap { value in
            (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
        }
    }
}

/// A frame carries its own source colour and layout through asynchronous decode and display.
struct Packed444FrameInfo: Equatable, Sendable {
    static let key = "RubyFunkPacked444" as CFString
    let layout: Packed444Layout
    let depth: UInt8
    let primaries: UInt8
    let transfer: UInt8
    let matrix: UInt8
    let fullRange: Bool

    var pixelFormat: OSType {
        depth == 8 ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            : kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
    }

    func accepts(_ buffer: CVPixelBuffer) -> Bool {
        CVPixelBufferGetPixelFormatType(buffer) == pixelFormat
            && CVPixelBufferGetWidth(buffer) == layout.codedWidth
            && CVPixelBufferGetHeight(buffer) == layout.codedHeight
    }

    func attach(to buffer: CVPixelBuffer) {
        let bytes = layout.bytes + [depth, primaries, transfer, matrix, fullRange ? 1 : 0]
        CVBufferSetAttachment(buffer, Self.key, Data(bytes) as CFData, .shouldNotPropagate)
    }

    static func read(_ buffer: CVPixelBuffer) -> Self? {
        guard let data = CVBufferCopyAttachment(buffer, key, nil) as? Data else { return nil }
        let bytes = Array(data)
        guard bytes.count == 22, let layout = Packed444Layout(bytes: Array(bytes.prefix(17))),
              bytes[17] == 8 || bytes[17] == 10 else { return nil }
        return Self(layout: layout, depth: bytes[17], primaries: bytes[18], transfer: bytes[19],
                    matrix: bytes[20], fullRange: bytes[21] != 0)
    }

    static func visibleSize(_ buffer: CVPixelBuffer) -> CGSize {
        if let info = read(buffer) { return CGSize(width: info.layout.width, height: info.layout.height) }
        return CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
    }
}

/// Integer texel reads restore full chroma before the presenter's ordinary scaling and CSC.
final class Packed444Restorer {
    static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void restore444(texture2d<float, access::read> carrierY [[texture(0)]],
                           texture2d<float, access::read> carrierUV [[texture(1)]],
                           texture2d<float, access::write> fullY [[texture(2)]],
                           texture2d<float, access::write> fullUV [[texture(3)]],
                           constant uint4& layout [[buffer(0)]],
                           uint2 p [[thread_position_in_grid]]) {
        if (p.x >= layout.x || p.y >= layout.y) return;
        float2 chroma;
        if ((p.x & 1) == 0) {
            chroma = carrierUV.read(uint2(p.x / 2, p.y)).rg;
        } else {
            uint row = layout.w / 2 + p.y;
            chroma = float2(carrierY.read(uint2(p.x / 2, row)).r,
                            carrierY.read(uint2(layout.z / 2 + p.x / 2, row)).r);
        }
        fullY.write(carrierY.read(p), p);
        fullUV.write(float4(chroma, 0, 1), p);
    }
    """

    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private var output: (y: MTLTexture, uv: MTLTexture)?

    init(device: MTLDevice) throws {
        self.device = device
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        guard let function = library.makeFunction(name: "restore444") else {
            throw NSError(domain: "RubyFunkPacked444", code: 1)
        }
        pipeline = try device.makeComputePipelineState(function: function)
    }

    /// Commands share the presenter's ordered queue, so one texture pair needs no CPU wait.
    func encode(
        _ buffer: MTLCommandBuffer, y: MTLTexture, uv: MTLTexture,
        info: Packed444FrameInfo
    ) -> (y: MTLTexture, uv: MTLTexture)? {
        let g = info.layout
        guard y.width == g.codedWidth, y.height == g.codedHeight,
              uv.width == g.codedWidth / 2, uv.height == g.codedHeight / 2 else { return nil }
        let yf: MTLPixelFormat = info.depth == 8 ? .r8Unorm : .r16Unorm
        let cf: MTLPixelFormat = info.depth == 8 ? .rg8Unorm : .rg16Unorm
        guard y.pixelFormat == yf, uv.pixelFormat == cf else { return nil }
        if output?.y.width != g.width || output?.y.height != g.height || output?.y.pixelFormat != yf {
            func make(_ format: MTLPixelFormat) -> MTLTexture? {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: format, width: g.width, height: g.height, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite]
                desc.storageMode = .private
                return device.makeTexture(descriptor: desc)
            }
            guard let fullY = make(yf), let fullUV = make(cf) else { return nil }
            output = (fullY, fullUV)
        }
        guard let output, let encoder = buffer.makeComputeCommandEncoder() else { return nil }
        encoder.label = "Packed 4:4:4 restore v1"
        encoder.setComputePipelineState(pipeline)
        for (index, texture) in [y, uv, output.y, output.uv].enumerated() {
            encoder.setTexture(texture, index: index)
        }
        var dimensions = SIMD4<UInt32>(UInt32(g.width), UInt32(g.height), UInt32(g.codedWidth), UInt32(g.codedHeight))
        encoder.setBytes(&dimensions, length: MemoryLayout.size(ofValue: dimensions), index: 0)
        encoder.dispatchThreads(MTLSize(width: g.width, height: g.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
        encoder.endEncoding()
        return output
    }
}
