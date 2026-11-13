// The core formats the stats overlay; these pin the Swift half: the line decode, and a live tier
// cycle that names its session and never moves the stored default.

import RubyFunkShared
import XCTest

@testable import RubyFunkKit

final class HudLineTests: XCTestCase {
    func testDecodesRoleTaggedLines() {
        let lines = RubyFunkConnection.HudLine.decode(
            "0\t120 fps · 24.3 Mb/s\n3\tlost 3 (2.4%)\nno tab here\n9\tunknown role\n")
        XCTAssertEqual(lines.map(\.text), ["120 fps · 24.3 Mb/s", "lost 3 (2.4%)", "unknown role"])
        XCTAssertEqual(lines.map(\.role), [.primary, .warn, .primary])
        XCTAssertEqual(RubyFunkConnection.HudLine.decode(""), [])
    }

    func testCycleRequestNamesItsSession() {
        let key = DefaultsKey.statsVerbosity
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set("detailed", forKey: key)
        let session = NSObject()
        let posted = expectation(forNotification: .rubyfunkStatsCycled, object: session)
        StatsVerbosity.requestCycle(for: session)
        wait(for: [posted], timeout: 1)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "detailed", "the stored tier moved")
    }
}
