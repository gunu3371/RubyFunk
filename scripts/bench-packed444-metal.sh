#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT HUP INT TERM
swiftc -parse-as-library -O -module-cache-path "$out/cache" \
    clients/apple/Sources/RubyFunkKit/Video/Packed444.swift \
    clients/apple/Sources/RubyFunkKit/Video/Packed444Probe.swift \
    tools/packed444-metal/main.swift -o "$out/packed444-metal"
"$out/packed444-metal"
