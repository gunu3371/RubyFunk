import CoreVideo
import Foundation
import Metal
import XCTest
@testable import RubyFunkKit

final class Packed444Tests: XCTestCase {
    func testCarrierOutputRequiresExactRangeAndSize() throws {
        let g = try XCTUnwrap(Packed444Layout(width: 65, height: 9))
        for depth: UInt8 in [8, 10] {
            let info = Packed444FrameInfo(layout: g, depth: depth, primaries: 1, transfer: 1, matrix: 1, fullRange: false)
            for full in [false, true] {
                let format: OSType = depth == 8
                    ? (full ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
                    : (full ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
                var buffer: CVPixelBuffer?
                XCTAssertEqual(CVPixelBufferCreate(nil, g.codedWidth, g.codedHeight, format, nil, &buffer), kCVReturnSuccess)
                XCTAssertEqual(info.accepts(try XCTUnwrap(buffer)), full)
            }
        }
    }

    func testLayoutRejectsUnknownVersionAndWrongCarrierSize() throws {
        let g = try XCTUnwrap(Packed444Layout(width: 2304, height: 1496))
        XCTAssertEqual(g.codedWidth, 2304)
        XCTAssertEqual(g.codedHeight, 2992)
        XCTAssertEqual(Packed444Layout(bytes: g.bytes), g)
        var bad = g.bytes
        bad[0] = 2
        XCTAssertNil(Packed444Layout(bytes: bad))
        bad = g.bytes
        bad[9] ^= 1
        XCTAssertNil(Packed444Layout(bytes: bad))
        XCTAssertNil(Packed444Layout(width: 0, height: 1))
        XCTAssertNil(Packed444Layout(width: 64, height: 8193))
    }

    func testMetalRestoresSharedRustVectorsExactly() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("No Metal device is available.")
        }
        let restorer = try Packed444Restorer(device: device)
        let clients = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = ProcessInfo.processInfo.environment["RF444_FIXTURES_DIR"].map(URL.init(fileURLWithPath:))
            ?? clients.appendingPathComponent("shared/packed444-v1")
        let files = try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "rf444" }.sorted { $0.path < $1.path }
        XCTAssertEqual(files.count, 6)
        for file in files {
            let bytes = Array(try Data(contentsOf: file))
            XCTAssertEqual(Array(bytes.prefix(4)), Array("RF44".utf8))
            let g = try XCTUnwrap(Packed444Layout(bytes: Array(bytes[12..<29])))
            let depth = bytes[4]
            let info = Packed444FrameInfo(layout: g, depth: depth, primaries: bytes[5],
                transfer: bytes[6], matrix: bytes[7], fullRange: bytes[8] != 0)
            let samples = stride(from: 29, to: bytes.count, by: 2).map {
                UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8
            }
            let yCount = g.codedWidth * g.codedHeight
            let cCount = yCount / 4
            let carrierCount = yCount + 2 * cCount
            let n = g.width * g.height
            XCTAssertEqual(samples.count, carrierCount + 3 * n)
            func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int) throws -> MTLTexture {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
                d.storageMode = .shared
                d.usage = [.shaderRead, .shaderWrite]
                return try XCTUnwrap(device.makeTexture(descriptor: d))
            }
            let y = try texture(depth == 8 ? .r8Unorm : .r16Unorm, g.codedWidth, g.codedHeight)
            let uv = try texture(depth == 8 ? .rg8Unorm : .rg16Unorm, g.codedWidth / 2, g.codedHeight / 2)
            let interleaved = (0..<cCount).flatMap { [samples[yCount + $0], samples[yCount + cCount + $0]] }
            func upload(_ texture: MTLTexture, _ codes: [UInt16]) {
                let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
                if depth == 8 {
                    codes.map { UInt8($0) }.withUnsafeBytes {
                        texture.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: g.codedWidth)
                    }
                } else {
                    codes.map { $0 << 6 }.withUnsafeBytes {
                        texture.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: g.codedWidth * 2)
                    }
                }
            }
            upload(y, Array(samples[..<yCount]))
            upload(uv, interleaved)
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let output = try XCTUnwrap(restorer.encode(command, y: y, uv: uv, info: info))
            let hostY = try texture(y.pixelFormat, g.width, g.height)
            let hostUV = try texture(uv.pixelFormat, g.width, g.height)
            let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
            blit.copy(from: output.y, to: hostY)
            blit.copy(from: output.uv, to: hostUV)
            blit.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            XCTAssertNil(command.error)
            func read(_ texture: MTLTexture, _ channels: Int) -> [UInt16] {
                let region = MTLRegionMake2D(0, 0, g.width, g.height)
                if depth == 8 {
                    var data = [UInt8](repeating: 0, count: n * channels)
                    data.withUnsafeMutableBytes {
                        texture.getBytes($0.baseAddress!, bytesPerRow: g.width * channels, from: region, mipmapLevel: 0)
                    }
                    return data.map(UInt16.init)
                }
                var data = [UInt16](repeating: 0, count: n * channels)
                data.withUnsafeMutableBytes {
                    texture.getBytes($0.baseAddress!, bytesPerRow: g.width * channels * 2, from: region, mipmapLevel: 0)
                }
                XCTAssertTrue(data.allSatisfy { $0 & 63 == 0 })
                return data.map { $0 >> 6 }
            }
            let restoredY = read(hostY, 1), restoredUV = read(hostUV, 2)
            XCTAssertEqual(restoredY, Array(samples[carrierCount..<carrierCount + n]), file.lastPathComponent)
            for p in 0..<2 {
                let component = (0..<n).map { restoredUV[$0 * 2 + p] }
                let start = carrierCount + (p + 1) * n
                XCTAssertEqual(component, Array(samples[start..<start + n]), file.lastPathComponent)
            }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(nil, 2, 2, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
            let tagged = try XCTUnwrap(buffer)
            info.attach(to: tagged)
            XCTAssertEqual(Packed444FrameInfo.read(tagged), info)
            XCTAssertEqual(Packed444FrameInfo.visibleSize(tagged), CGSize(width: g.width, height: g.height))
        }
    }
}
