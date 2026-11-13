// The Controller type slot's marks. Its step order and words replay the shared vectors in
// `OverlayActionsTests.testSharedPadTypeCycle`.

import XCTest
@testable import RubyFunkKit

final class PadTypeTests: XCTestCase {
    /// A name with no imageset draws nothing at runtime, so check the catalog itself.
    func testEveryPickedTypeShipsAMark() {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/RubyFunkKit/Resources/PadMarks.xcassets")
        for type in RubyFunkConnection.GamepadType.ringCycle where type != .auto {
            guard let name = type.markName else { return XCTFail("\(type) has no outline") }
            let pdf = catalog.appendingPathComponent("\(name).imageset/\(name).pdf")
            XCTAssertTrue(FileManager.default.fileExists(atPath: pdf.path), "\(name).pdf missing")
        }
        XCTAssertNil(RubyFunkConnection.GamepadType.auto.mark)
    }
}
