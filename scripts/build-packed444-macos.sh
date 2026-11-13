#!/usr/bin/env bash
# Build the local Mac client with matching Rust headers and the Packed 4:4:4 tests.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'Run this script on a Mac with Xcode and rustup.' >&2
    exit 1
fi
git rev-parse HEAD
sw_vers
xcodebuild -version
rustup target add aarch64-apple-darwin x86_64-apple-darwin
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}" bash scripts/build-xcframework.sh
codesign --verify --deep --strict clients/apple/RubyFunkCore.xcframework
swift test --package-path clients/apple --filter Packed444Tests
xcodebuild -project clients/apple/RubyFunk.xcodeproj -scheme RubyFunk \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath target/validation/mac-client CODE_SIGNING_ALLOWED=NO \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG RUBYFUNK_LOCAL_KEYCHAIN' build
app=target/validation/mac-client/Build/Products/Debug/RubyFunk.app
codesign --force --deep --sign - --entitlements clients/apple/local-macos.entitlements "$app"
codesign --verify --deep --strict "$app"
printf 'Client ready: %s\n' "$app"
