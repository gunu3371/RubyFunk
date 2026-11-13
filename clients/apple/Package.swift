// swift-tools-version: 5.9
// RubyFunkKit — Swift wrapper around the rubyfunk-core C ABI (punktfunk/1 client connector) plus the
// SwiftUI/VideoToolbox presentation layer. Build RubyFunkCore.xcframework first:
//   bash ../../scripts/build-xcframework.sh   (on a Mac; see README.md)
import PackageDescription

let package = Package(
    name: "RubyFunkKit",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .visionOS("26.0")],
    products: [
        .library(name: "RubyFunkKit", targets: ["RubyFunkKit"]),
        // Dependency-free foundation (stored-host model + JSON codec, settings keys, App-Group
        // constant, deep-link grammar, Live Activity attributes). A separate PRODUCT so the widget
        // extension — which must never link RubyFunkKit (Rust staticlib + presentation layer) —
        // can link this and nothing else. RubyFunkKit re-exports it (see SharedReexport.swift).
        .library(name: "RubyFunkShared", targets: ["RubyFunkShared"]),
        .executable(name: "RubyFunkClient", targets: ["RubyFunkClient"]),
    ],
    dependencies: [
        // Progressive backdrop blur with no material tint; `pf-console-ui`'s `blur.rs` follows it.
        // GlurBackdrop first ships in 2.0.
        .package(url: "https://github.com/joogps/Glur.git", from: "2.0.0"),
    ],
    targets: [
        .binaryTarget(name: "RubyFunkCore", path: "RubyFunkCore.xcframework"),
        // No dependencies by design — an extension process links this alone.
        .target(name: "RubyFunkShared"),
        .target(
            name: "RubyFunkKit",
            dependencies: ["RubyFunkCore", "RubyFunkShared"],
            // OSS attribution shown by the app's Acknowledgements screen. Bundled here (not in the
            // app target) so it rides along via Bundle.module in both `swift build` and the Xcode
            // app, which links the RubyFunkKit product. Refresh with
            // scripts/gen-third-party-notices.sh (it copies the generated file into Resources/).
            resources: [
                .copy("Resources/THIRD-PARTY-NOTICES.txt"),
                .copy("Resources/LICENSE-MIT.txt"),
                .copy("Resources/LICENSE-APACHE.txt"),
                // Geist (SIL OFL 1.1) — the brand typeface, shared with rubyfunk-website.
                // Registered with Core Text at first use; see BrandFont.swift.
                .copy("Resources/Fonts"),
                // The host cards' OS marks (template vector imagesets generated from the
                // assets/os-icons masters by scripts/gen-os-icons.sh — per-mark provenance and
                // licensing in that README). `.process` compiles the catalog; loaded via
                // OsIcon.swift.
                .process("Resources/OsIcons.xcassets"),
                // The launcher tiles' brand marks (template vector imagesets generated from the
                // assets/launcher-icons masters by scripts/gen-launcher-icons.sh — per-mark
                // provenance and licensing in that README). Loaded via LauncherIcon.swift.
                .process("Resources/LauncherIcons.xcassets"),
                // The Controller type quick action's pad outlines (scripts/gen-pad-marks.py, from
                // the console's Kenney outlines). Loaded via PadType.swift.
                .process("Resources/PadMarks.xcassets"),
            ],
            linkerSettings: [
                // Rust staticlib system deps.
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedLibrary("resolv"),
                // Skia, for the console (clients/apple/native).
                .linkedLibrary("c++"),
                .linkedFramework("Metal"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ApplicationServices", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS, .tvOS, .visionOS])),
                .linkedFramework("MobileCoreServices", .when(platforms: [.iOS, .tvOS, .visionOS])),
            ]
        ),
        // Development app shell (swift run RubyFunkClient): connect form → stream + input.
        // (The tvOS slide-transition package is referenced by the Xcode PROJECT only —
        // its manifest breaks SwiftPM whole-graph validation on macOS, and only the
        // RubyFunk-tvOS target links it; the #if os(tvOS) import never compiles here.)
        .executableTarget(
            name: "RubyFunkClient",
            dependencies: [
                "RubyFunkKit",
                .product(name: "GlurBackdrop", package: "Glur"),
            ]),
        // RubyFunkCore is a direct dep too so the wire tests can name the C ABI's
        // `RubyFunkInputEvent` / `RUBYFUNK_INPUT_KIND_*` when asserting the gamepad byte layout.
        .testTarget(
            name: "RubyFunkKitTests",
            dependencies: ["RubyFunkKit", "RubyFunkShared", "RubyFunkCore"],
            resources: [
                // PyroWave golden fixtures: host-encoded AUs + upstream-decoded reference
                // planes (regenerate with rubyfunk-host's `pyrowave_dump_golden` on a
                // Vulkan box — see PyroWaveDecoderTests.swift).
                .copy("PyroWaveFixtures")
            ]),
    ]
)
