# Packed 4:4:4 validation

Recorded 2026-11-07 on Apple M4, macOS 27.2. Windows AMD equipment is not connected to this run.

## Results

| Check | Result |
| --- | --- |
| CPU permutation, padding, odd sizes, 8/10-bit codes | 4 Rust tests pass |
| Core library including hello/config compatibility and source CICP tests | 1097 pass, 8 ignored |
| C ABI unit tests and compiled C caller | 42 unit tests and 1 C harness pass |
| Capture/driver contract tests | 105 capture and 161 driver tests pass |
| Windows encoder/session Clippy | `--tests --target x86_64-pc-windows-msvc -- -D warnings` passes |
| Windows encoder/session cross-check | `cargo check -p pf-encode-session --tests --target x86_64-pc-windows-msvc` passes |
| Windows host cross-check | Blocked by missing Windows C headers/runtime (`zstd-sys`: `string.h`) |
| macOS host common code | `cargo check -p punktfunk-host --no-default-features` passes; host test binary builds, 15 control tests pass |
| Apple native static library/XCFramework | arm64 release build succeeds; unsigned local XCFramework |
| Apple Swift library and test executable | Build succeeds |
| Shared Rust vectors on the M4 Metal kernel | 6 vectors pass, bit-exact Y/U/V after restoration |
| Swift layout, carrier checks and Metal tests | 3 pass |
| AMF HLSL execution / actual encode | Not run; needs Windows D3D11 and AMD runtime |
| Windows capture-worker cross-check | Blocked by missing Visual Studio CMake generator |
| Windows driver build, signing and install | Not run; needs Windows SDK/WDK |
| Windows AMD → macOS live stream | Not run |

The first broad Rust run had sandbox socket denials and a timing-test failure under parallel
build load. The reported core result is the subsequent unrestricted, serial test run.
The Apple build uses the repository's verified Skia archive and arm64 slice. The local signing
attempt finds ambiguous development identities; it leaves the XCFramework unsigned. It is not
a signed universal release artifact.

## Restore-only GPU sample

Production Metal kernel, original 2304×1496, carrier 2304×2992, 20 warm-up dispatches and 240
timed dispatches per depth. Commands are submitted individually and completed before the next
sample. Times are command-buffer GPU durations, without CSC, presentation, codec or network.
Other build work was active; this is not an isolated performance qualification.

| Depth | Median | p95 | Maximum |
| --- | --- | --- | --- |
| 8 | 0.3033 ms | 0.6856 ms | 1.9926 ms |
| 10 | 0.3305 ms | 0.3479 ms | 0.3643 ms |

Both HEVC8 and AV1-8 decoder session creation accept the target coded geometry on this M4.
That does not demonstrate hardware decode of an AMF stream, sustained 120 fps, a complete
8.33 ms frame budget or end-to-end latency. Ten-bit kernel timing does not enable ten-bit
stream negotiation.

## Reproduce

Install the pinned Rust toolchain, CMake and Xcode first. This run used temporary Rust/CMake
installations under `/tmp`; it did not change the system PATH or Xcode selection.

```sh
cargo test -p pf-packed444
cargo test -p punktfunk-core --features quic --lib -- --test-threads=1
cargo test -p punktfunk-ffi --features quic
cargo test -p pf-capture -p pf-driver-proto --lib
cargo check -p pf-encode-session --target x86_64-pc-windows-msvc
cargo test -p gen-headers
swift test --package-path clients/apple --filter Packed444Tests
sh scripts/bench-packed444-metal.sh
```

Swift tests need an ABI-matched macOS XCFramework. Use `scripts/build-xcframework.sh` for normal
packaging. This session built only arm64 for the available Mac. Swift tests can explicitly skip
the GPU test when Metal is absent; a skip is not a GPU pass.

On Windows, compile/run the actual converter test, including deferred conversion, odd sizes,
padding, both ranges and 8/10-bit BGRA conversion:

```powershell
cargo test -p pf-encode-session packed444_rgb_pass -- --ignored --nocapture
```

It requires planar NV12/P010 render targets and fails if no D3D11 device is available. Build the
host and `punktfunk-capture-worker`, then the separate `packaging/windows/drivers` workspace
with an x64 Windows machine, Visual Studio C++ build tools, Windows SDK/WDK, LLVM/libclang
and the AMD driver/AMF runtime. The existing `scripts/windows/README.md` describes the build
environment. Install matching protocol-10 components together.

The shared `.rf444` fixtures live in `clients/shared/packed444-v1`. Regenerate with:

```sh
cargo run -p pf-packed444 --example vectors -- clients/shared/packed444-v1
```

Fixture bytes: `RF44`, depth/primaries/transfer/matrix/range (five bytes), three zero reserved
bytes, the 17-byte layout, then LE `u16` code values: dense planar carrier Y/U/V followed by
original planar Y/U/V. Ten-bit fixture codes are unshifted; P010 upload shifts them by six.
Three geometries (1×1, 3×2, 65×9), each at 8 and 10 bits, exercise parity, edges and padding.
Regeneration should produce no diff. Additional clients must reproduce the original planes.

## Required live comparison

Record AMD GPU and driver, Windows build, Mac model/macOS, display refresh, SDR/HDR state,
codec, resolution, encoder settings, FEC policy, network path and display fit. Start with SDR8.
Use the same 2304×1496, 120 Hz, AV1 and 219,000 kbps setting for both ordinary and packed runs.
Reconnect with Full chroma off/on, and verify the selected layout in host logs/status.

Use deterministic captures of coloured text/code, one-pixel lines, static UI, timed scroll and
a game replay. Capture several warm runs and compare both still and moving frames, including
startup/IDR quality. Do not infer picture improvement from the lossless permutation tests.
Compare decoded source-sized RGB crops, accounting for identical source CICP and display scaling.

Collect encoder submit→publish timings, decode pull→completion, GPU restore and present timings,
actual source/encoded/decoded/presented fps, pool/decoder/presenter drops, and glass-to-glass
latency with a shared visual clock or high-speed capture. Report medians/p95 and sample counts.
Use existing host timing telemetry and client HUD alongside packet/interface counters; separate
codec delay from capture pacing, queues, FEC wait and display scheduling.

219 Mbps is a setting, not a measurement. This base already derives encoder payload from a
session wire budget, reserving audio/FEC/framing (`native/bitrate.rs`, `EncDerive`). Record both
the requested setting and the encoder's applied bitrate. Measure video AU bytes, repair/FEC,
control/audio, IP/UDP/QUIC and link-layer traffic separately; do not add FEC twice or describe
219 Mbps as observed network traffic. Packed pixels double the carrier work at the same setting.

No live values for encode/decode delay, stream fps, drops, total latency, actual traffic or
picture-quality gain are available from this run. Ten-bit SDR/HDR requires a separate colour,
static-HDR metadata and range-preservation roundtrip before lifting the negotiation gate.
