import XCTest
import RubyFunkCore
@testable import RubyFunkKit

final class FunctionKeyTests: XCTestCase {
    func testHIDFunctionKeys() {
        for i in 0..<12 {
            XCTAssertEqual(InputCapture.hidToVK[0x3A + i], UInt32(0x70 + i))
        }
        for i in 0..<7 {
            XCTAssertEqual(InputCapture.hidToVK[0x68 + i], UInt32(0x7C + i))
        }
        XCTAssertEqual(InputCapture.hidToVK[0x46], 0x2C) // Print Screen follows F12, not F13.
        XCTAssertNil(InputCapture.hidToVK[0x6F]) // F20 remains outside this change.
    }

    #if os(macOS)
    func testNSEventFunctionKeysMatchHID() {
        let codes: [UInt16] = [
            0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F,
            0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50,
        ]
        for (i, code) in codes.enumerated() {
            let hid = i < 12 ? 0x3A + i : 0x68 + i - 12
            XCTAssertEqual(InputCapture.keyCodeToVK[code], UInt32(0x70 + i))
            XCTAssertEqual(InputCapture.keyCodeToVK[code], InputCapture.hidToVK[hid])
        }
        XCTAssertNil(InputCapture.keyCodeToVK[0x5A]) // kVK_F20
    }
    #endif

    func testExtendedFunctionKeyPressAndReleaseWireEvents() throws {
        for i in 0..<7 {
            let vk = try XCTUnwrap(InputCapture.hidToVK[0x68 + i])
            for layout in [ModifierLayout.mac, .windows] {
                let mapped = InputCapture.applyModifierLayout(vk, layout)
                XCTAssertEqual(mapped, UInt32(0x7C + i))
                let press = RubyFunkInputEvent.key(mapped, down: true)
                let release = RubyFunkInputEvent.key(mapped, down: false)
                XCTAssertEqual(press.kind, UInt8(RUBY_FUNK_INPUT_KIND_KEY_DOWN.rawValue))
                XCTAssertEqual(release.kind, UInt8(RUBY_FUNK_INPUT_KIND_KEY_UP.rawValue))
                XCTAssertEqual(press.code, vk)
                XCTAssertEqual(release.code, vk)
                XCTAssertEqual(press.flags, 0)
                XCTAssertEqual(release.flags, 0)
            }
        }
    }
}
