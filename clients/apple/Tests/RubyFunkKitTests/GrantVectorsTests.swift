// `crates/core/rubyfunk-core/testdata/grant-vectors.json`, which core writes, against the Swift
// grant rule: the legacy-full read and the level a mask labels as. The web console and Kotlin
// replay the same file.

import XCTest

@testable import RubyFunkKit

final class GrantVectorsTests: XCTestCase {
    func testLevelsMatchTheCoreVectors() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RubyFunkKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // apple
            .deletingLastPathComponent() // clients
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("crates/core/rubyfunk-core/testdata/grant-vectors.json")
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(root["all"] as? Int, Int(RubyFunkConnection.grantAll))
        XCTAssertEqual(root["all_pre_power"] as? Int, Int(RubyFunkConnection.grantAllPrePower))
        XCTAssertEqual(root["all_pre_manage"] as? Int, Int(RubyFunkConnection.grantAllPreManage))
        let levels: [String: RubyFunkConnection.AccessLevel] = [
            "full": .fullControl, "controller": .controllerOnly, "view": .viewOnly,
            "custom": .custom,
        ]
        for c in try XCTUnwrap(root["masks"] as? [[String: Any]]) {
            let mask = try UInt32(XCTUnwrap(c["mask"] as? Int))
            let normalized = try UInt32(XCTUnwrap(c["normalized"] as? Int))
            XCTAssertEqual(RubyFunkConnection.normalizedGrants(mask), normalized, "mask \(mask)")
            let level = try XCTUnwrap(levels[c["level"] as? String ?? ""], "mask \(mask)")
            XCTAssertEqual(RubyFunkConnection.AccessLevel(grants: mask), level, "mask \(mask)")
        }
    }
}
