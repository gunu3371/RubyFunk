import Foundation
import Metal

@main struct Packed444Benchmark {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fputs("No Metal device is available.\n", stderr)
            exit(77)
        }
        let restorer = try Packed444Restorer(device: device)
        let g = Packed444Layout(width: 2304, height: 1496)!
        print("GPU: \(device.name)")
        print("Restore only: source 2304x1496, carrier 2304x2992; no codec or network")
        for depth: UInt8 in [8, 10] {
            func input(_ format: MTLPixelFormat, _ width: Int, _ height: Int, channels: Int) throws -> MTLTexture {
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
                desc.storageMode = .shared
                desc.usage = [.shaderRead]
                guard let texture = device.makeTexture(descriptor: desc) else { throw Failure.allocation }
                let count = width * height * channels
                let region = MTLRegionMake2D(0, 0, width, height)
                if depth == 8 {
                    (0..<count).map { UInt8(truncatingIfNeeded: $0 * 17 + $0 / width * 53) }.withUnsafeBytes {
                        texture.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * channels)
                    }
                } else {
                    (0..<count).map { UInt16(($0 * 17 + $0 / width * 53) & 1023) << 6 }.withUnsafeBytes {
                        texture.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * channels * 2)
                    }
                }
                return texture
            }
            let y = try input(depth == 8 ? .r8Unorm : .r16Unorm, g.codedWidth, g.codedHeight, channels: 1)
            let uv = try input(depth == 8 ? .rg8Unorm : .rg16Unorm, g.codedWidth / 2, g.codedHeight / 2, channels: 2)
            let info = Packed444FrameInfo(layout: g, depth: depth, primaries: 1, transfer: 1, matrix: 1, fullRange: true)
            var elapsed: [Double] = []
            for i in 0..<260 {
                guard let cb = queue.makeCommandBuffer(), restorer.encode(cb, y: y, uv: uv, info: info) != nil else {
                    throw Failure.allocation
                }
                cb.commit()
                cb.waitUntilCompleted()
                if let error = cb.error { throw error }
                if i >= 20 { elapsed.append((cb.gpuEndTime - cb.gpuStartTime) * 1000) }
            }
            elapsed.sort()
            print(String(format: "depth=%d GPU_ms median=%.4f p95=%.4f max=%.4f n=%d",
                depth, elapsed[elapsed.count / 2], elapsed[elapsed.count * 95 / 100], elapsed.last!, elapsed.count))
        }
        print("Decoder session admission at this geometry (not a throughput benchmark):")
        print(Packed444Probe.capabilities(width: g.width, height: g.height, fps: 120))
    }

    enum Failure: Error { case allocation }
}
