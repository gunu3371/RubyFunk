---
title: Testing
description: Prove a change before you push it — the workspace suite, the per-area checks, and a live host from source against a client.
---

The commands that prove a change: the workspace suite, the checks for each area, and a host built
from source streaming to a client.

## The workspace suite

The core of CI's `rust` job, on Linux with the
[workspace packages](/docs/developers/build-from-source#workspace-prerequisites):

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked     # unit, loopback, proptest, C ABI harness
```

Use `--locked` as CI does, or a silent `Cargo.lock` update passes locally and fails CI. To run one
crate, `cargo test -p <package>`; package names are in
[Architecture](/docs/developers/architecture#where-the-code-lives). Tests that need a GPU, a
compositor or a display skip themselves or are `#[ignore]`d.

Two traps:

- `rubyfunk-core` and `rubyfunk-ffi` alone build without their `quic` feature, which drops the
  connection tests. Use `cargo test -p rubyfunk-core -p rubyfunk-ffi --features quic`.
- `rubyfunk-host` has no library target: pass test filters after `--`, never `--lib`.

## Per-area checks

| Area | Command |
|---|---|
| FEC under loss, no network | `cargo run -p loss-harness` |
| C ABI links from C | `bash crates/client/rubyfunk-ffi/tests/c/run.sh` |
| Scroll, wire and compatibility | `cargo test -p rubyfunk-core --features quic scroll` |
| Scroll, host mapping (any OS) | `cargo test -p pf-inject --lib scroll` |
| Touch and scroll in the presenter (macOS too) | `cargo test -p pf-presenter --no-default-features` |
| Linux GPU encode backends | `cargo test -p pf-encode --locked --features nvenc,vulkan-encode,pyrowave` |
| Host without GameStream | `cargo clippy -p rubyfunk-host --no-default-features --features pyrowave --all-targets -- -D warnings` |
| Guided installer | `cargo test -p rubyfunk-setup` and `sh scripts/ci/check-installer-behavior.sh` |
| Settings table in the docs | `cargo test -p pf-host-config docs_table_is_current` |
| Windows code from another OS | `scripts/xcheck.sh` |

`scripts/xcheck.sh` type-checks and lints the Windows code of the capture, display and frame crates.
It needs the target installed: `rustup target add x86_64-pc-windows-msvc`. Linux-only code needs a
Linux box or container, because pipewire's build script needs the Linux library.

A settings change regenerates the table in [Configuration](/docs/configuration) with
`UPDATE_SETTINGS_DOCS=1 cargo test -p pf-host-config docs_table_is_current`.

## JavaScript packages

Run `bun install` in the directory first. Build before typecheck: the build generates code the
typecheck imports.

| Directory | Command |
|---|---|
| `web/` | `bun run check && bun run build && bun run lint && bun run test` |
| `docs-site/` | `bun run build && bun run lint` |
| `sdk/` | `bun run typecheck && bun run test` |
| `plugin-kit/` | `bun run check && bun run typecheck && bun run test` |
| `clients/decky/` | `pnpm install && pnpm run typecheck`, then `python3.13 scripts/test-backend.py` |

For a docs change, also run `sh scripts/ci/check-docs-links.sh` and
`sh scripts/ci/check-docs-drift.sh` from the repo root.

## Apple client

Build `RubyFunkCore.xcframework` first
([Build from source](/docs/developers/build-from-source#apple-client)), then from `clients/apple`:

```sh
swift test                  # macOS units; tests that need a host skip without one
bash test-loopback.sh       # synthetic hosts on 127.0.0.1, then the integration tests
swift test --filter ScrollCaptureTests
xcodebuild -project RubyFunk.xcodeproj -scheme RubyFunk-iOS \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The tvOS scheme is the same with `-scheme RubyFunk-tvOS` and `'generic/platform=tvOS Simulator'`.
`ScrollCaptureTests` needs an xcframework built from the same tree, whose header defines
`RUBYFUNK_FEATURE_QUIC`; `build-xcframework.sh` produces that.

## Android client

From `clients/android`, with the toolchain from
[Build from source](/docs/developers/build-from-source#android-client):

```sh
./gradlew :kit:testDebugUnitTest :app:testDebugUnitTest -PexcludeScreenshots
```

## Windows drivers

From `packaging/windows/drivers`, as in
[Build from source](/docs/developers/build-from-source#windows-drivers):

```powershell
..\drivers-cargo.ps1 'test --locked -p pf-umdf-util'
..\drivers-cargo.ps1 'clippy --locked -p pf-umdf-util -p pf-xusb -p pf-gamepad -p pf-mouse -p wdk-iddcx -p pf-vdisplay --all-targets -- -D warnings'
```

## Run a host from source against a client

**Without a desktop.** The synthetic host speaks `punktfunk/2` with generated frames and runs
anywhere the host compiles, macOS included. In two terminals, start it and connect the probe,
which byte-checks the frames:

```sh
cargo run -rp rubyfunk-host -- rubyfunk1-host --source synthetic --allow-tofu
cargo run -rp rubyfunk-probe -- --connect 127.0.0.1:9777
```

`--allow-tofu` lets an unpaired client connect; leave it out to test pairing.

**On a Linux desktop.** Start the host inside the session, then, in a second terminal, open a
pairing window:

```sh
cargo run -rp rubyfunk-host -- serve
cargo run -rp rubyfunk-host -- ctl pair arm       # prints the PIN
```

On the client box, pair and stream with the CLI (it starts `rubyfunk-session` from beside itself):

```sh
cargo build --release -p rubyfunk-cli -p rubyfunk-client-session
target/release/rubyfunk pair <host-ip>            # asks for the PIN
target/release/rubyfunk launch <host-ip>
```

Any installed client pairs the same way. `rubyfunk-probe` exercises single planes against a live
host: `--input-test`, `--mic-test`, `--touch-test`, `--rich-input-test`. Its flags are in
[clients/probe](https://git.unom.io/unom/punktfunk/src/branch/main/clients/probe/README.md). For
the web console against this host, run `bun run dev` in `web/`.
