// The video-capability byte, which is a wire promise: every bit says the decoder and the
// present path can take what the host is then free to send.
//
// Depth and HDR used to be one ask — the client sent 10-bit only alongside HDR10, so an SDR
// desktop always arrived at 8-bit and gradients banded. They are separate now, and the pair
// that must not drift is "HDR without the depth": the host would upgrade the stream and hand
// the decoder Main10 the client never claimed.

import XCTest

@testable import RubyFunkKit

final class VideoCapsTests: XCTestCase {
    func testDepthAndHDRAreSeparateAsks() {
        XCTAssertEqual(
            RubyFunkConnection.videoCaps(tenBit: false, hdr: false, chroma444: false), 0,
            "nothing advertised is the 8-bit BT.709 SDR stream")

        // `ten_bit_sdr`: Main10 for a desktop, and no HDR promise with it.
        XCTAssertEqual(
            RubyFunkConnection.videoCaps(tenBit: true, hdr: false, chroma444: false),
            RubyFunkConnection.videoCap10Bit)

        // HDR carries the depth even when the ten-bit ask was off — the two cannot separate
        // in that direction, because HDR10 is Main10.
        XCTAssertEqual(
            RubyFunkConnection.videoCaps(tenBit: false, hdr: true, chroma444: false),
            RubyFunkConnection.videoCap10Bit | RubyFunkConnection.videoCapHDR)

        XCTAssertEqual(
            RubyFunkConnection.videoCaps(tenBit: true, hdr: true, chroma444: true),
            RubyFunkConnection.videoCap10Bit | RubyFunkConnection.videoCapHDR
                | RubyFunkConnection.videoCap444)

        // 4:4:4 rides on whatever depth was asked for, and never implies one.
        XCTAssertEqual(
            RubyFunkConnection.videoCaps(tenBit: false, hdr: false, chroma444: true),
            RubyFunkConnection.videoCap444)
    }
}
