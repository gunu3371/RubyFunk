// The brand color, in the dependency-free foundation so EVERY process can use it — the widget
// extension links RubyFunkShared alone (never RubyFunkKit's Rust staticlib), and before this
// moved here the Live Activity / widgets fell back to `.tint` = system blue.

import SwiftUI

public extension Color {
    /// White labels retain contrast on filled actions in either appearance.
    static let brandFill = Color(red: 0xC4 / 255, green: 0x12 / 255, blue: 0x42 / 255)

    /// Ruby on light surfaces and pink on dark surfaces keep controls readable.
    /// Explicit values also give widgets the same accent without an asset catalog.
    static let brand: Color = {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xFF / 255, green: 0x47 / 255, blue: 0x7B / 255, alpha: 1)
                : UIColor(red: 0xC4 / 255, green: 0x12 / 255, blue: 0x42 / 255, alpha: 1)
        })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0xFF / 255, green: 0x47 / 255, blue: 0x7B / 255, alpha: 1)
                : NSColor(red: 0xC4 / 255, green: 0x12 / 255, blue: 0x42 / 255, alpha: 1)
        })
        #else
        // Non-Apple fallback: the light brand value, so all branches agree on a canonical color.
        return Color(red: 0xC4 / 255, green: 0x12 / 255, blue: 0x42 / 255)
        #endif
    }()
}
