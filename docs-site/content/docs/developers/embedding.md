---
title: Embed the core (C ABI)
description: Build a client for a platform without a RubyFunk app by linking the rubyfunk-ffi C ABI.
---

Link `rubyfunk-ffi` into your own client and it speaks the whole protocol for you: the QUIC
handshake, pairing, the encrypted media path, FEC and loss recovery, clock sync. You decode
video, present it, play audio and read input. The contract is
[`include/rubyfunk_core.h`](https://git.unom.io/unom/punktfunk/src/branch/main/include/punktfunk_core.h):
every symbol carries a doc comment, and this page is the map to it. A Rust client depends on
`rubyfunk-core` with `features = ["quic"]` instead, as the Android client does.

## Build and link

```sh
cargo build -p rubyfunk-ffi --features quic --release
```

One build writes both library kinds to `target/release/`: `librubyfunk_ffi.a` (static),
`librubyfunk_ffi.so` / `.dylib` / `rubyfunk_ffi.dll` (dynamic). `cargo run -p gen-headers`
regenerates the header from
[`rubyfunk-ffi`](https://git.unom.io/unom/punktfunk/src/branch/main/crates/client/punktfunk-ffi/src/lib.rs)
with cbindgen; the header is checked in, and CI fails when it is stale.

Compile your code with `-DRUBYFUNK_FEATURE_QUIC`. The whole client API (`rubyfunk_connect*`,
`rubyfunk_connection_*`, `rubyfunk_pair`, `rubyfunk_probe`) sits behind that define. Without it
the header declares only the raw loopback session (`rubyfunk_session_*`), which the tests use.

```sh
cc -std=c11 -DRUBYFUNK_FEATURE_QUIC -I include -c myclient.c
cc myclient.o -L target/release -lrubyfunk_ffi -o myclient          # dynamic
NATIVE=$(cargo rustc -p rubyfunk-ffi --features quic --release --lib --crate-type staticlib \
  -- --print native-static-libs 2>&1 | sed -n 's/.*native-static-libs: //p' | tail -1)
cc myclient.o target/release/librubyfunk_ffi.a $NATIVE -o myclient     # static
```

To cross-compile, `rustup target add <triple>`, set `CC_<triple>` and
`CARGO_TARGET_<TRIPLE>_LINKER` to your SDK's compiler, and add `--target <triple>`. The QUIC build
compiles aws-lc (TLS) and libopus from C, so the target needs a working C compiler. Apple builds go
through `scripts/build-xcframework.sh`, which packs the C ABI into `RubyFunkCore.xcframework` with
`RUBYFUNK_FEATURE_QUIC` already defined. Toolchain setup:
[Build from source](/docs/developers/build-from-source).

## Check the version first

```c
if (rubyfunk_abi_version() != RUBYFUNK_ABI_VERSION) abort(); /* library ≠ header */
```

Do this before any other call: structs without a size prefix (`RubyFunkHidOutput`,
`RubyFunkAudioPcm`) rely on it to stop an older binary passing a slot that is too small. Structs
that start with `struct_size` (`RubyFunkConnectOpts`, `RubyFunkRichInputEx`, `RubyFunkConfig`)
are zero-initialised, then `struct_size = sizeof(T)`; the core rejects a size below its minimum.
`RUBYFUNK_WIRE_VERSION` is the protocol, which the core checks against the host itself. ABI
changes per release: [`CHANGELOG.md`](https://git.unom.io/unom/punktfunk/src/branch/main/CHANGELOG.md).

## Rules for every call

- **Status.** Fallible calls return `RubyFunkStatus`: `RUBY_FUNK_STATUS_OK` is 0, errors are
  negative. In pull loops, `NO_FRAME` means nothing arrived before the timeout and `CLOSED` means
  the session ended. `-20` to `-37` (`RUBYFUNK_STATUS_REJECTED_*`) is the host refusing you; show
  each as its own sentence. `REJECTED_PROFILE_LOCKED` (`-37`) asks for the profile's password:
  prompt, then connect again with `unlock`. A Rust panic never crosses the boundary; it returns
  `PANIC` (`-99`).
- **One thread per plane.** Video, audio, rumble, HID output, HDR metadata, host timing, cursor,
  clipboard and pad audio are separate queues. Pull each from at most one thread; different planes
  may run concurrently.
- **Borrowed buffers.** `next_au`, `next_audio`, `next_audio_pcm`, `next_cursor_shape` and
  `next_clipboard` hand back pointers into core memory that stay valid until your next pull on the
  same plane. Decode or copy before you pull again.
- **Senders and setters** (`send_*`, `set_*`, `request_*`) enqueue and return, from any thread.
  `rubyfunk_connect*`, `rubyfunk_pair`, `rubyfunk_probe` and `rubyfunk_wake_on_lan` block on
  the network: keep them off your UI thread.

## Lifecycle

1. **Logs (optional).** `rubyfunk_set_log_callback(3, cb, user)` routes the core's log lines to
   your sink; `3` is info and up. The callback runs on core threads.
2. **Identity, once per install.** `rubyfunk_generate_identity` writes a certificate and key as
   PEM (4096-byte buffers are enough). Store both securely and pass them to every pair and connect.
   Hosts require pairing unless started with `--open`, so an anonymous connect gets refused.
3. **Admission.** Either connect with the identity and let the operator click **Approve** in the
   console (the connect waits up to `timeout_ms`; the host holds the request for 3 minutes), or
   call `rubyfunk_pair` with the PIN the host shows (`CRYPTO` means a wrong PIN). See
   [Pairing](/docs/pairing). Store the host fingerprint you get back and pass it as `pin_sha256` on
   every later connect.
4. **Connect** with `rubyfunk_connect_opts` (below), read the resolved session, and start one
   thread per plane you use. On NULL, `status_out` says why.
5. **Tear down.** Stop your pull threads, call `rubyfunk_connection_disconnect_quit` only when the
   user chose to stop (the host then drops the display instead of holding it for a reconnect), then
   `rubyfunk_connection_close`, which joins the core's threads and frees the handle.

Discovery isn't part of the C ABI. Browse mDNS for `_rubyfunk._udp` with the platform's API, or
let the user type an address. `rubyfunk_probe` checks a known address; compare its
`observed_sha256_out` with the stored fingerprint, since any machine on that address answers.
`rubyfunk_wake_on_lan` wakes a host from the MACs in its mDNS `mac` TXT record.

## Connect

Fill `RubyFunkConnectOpts`; zero means auto or unspecified for every field. Advertise only codecs
and caps you can decode and present, because the host upgrades to 10-bit, HDR, 4:4:4 or AV1 when
you set the bit. `video_codecs = 0` means HEVC only.

| Field | Meaning |
| --- | --- |
| `host`, `port` | Required. The host's native port ([Ports](/docs/ports)). |
| `width`, `height`, `refresh_hz` | The mode the host creates its virtual display at. |
| `video_codecs`, `preferred_codec` | `RUBYFUNK_CODEC_*` bits you decode; one bit to prefer. |
| `video_caps` | `RUBYFUNK_VIDEO_CAP_10BIT` / `_HDR` / `_444`. |
| `audio_channels` | 2, 6 or 8. |
| `audio_rate_hz`, `audio_bits` | Leave 0/0 for Opus. Any non-zero pair asks for lossless PCM. |
| `gamepad`, `compositor` | `RUBYFUNK_GAMEPAD_*` / `RUBYFUNK_COMPOSITOR_*`; 0 lets the host pick. |
| `bitrate_kbps` | 0 = host default. |
| `client_caps` | `RUBYFUNK_CLIENT_CAP_CURSOR` only if you draw the cursor yourself. |
| `video_fit` | `RUBYFUNK_VIDEO_FIT_*`: how your view fills when the frame's shape differs. |
| `preset_id`, `preset_name` | The settings preset this dial names; the host shows it and hands it to hooks. |
| `pin_sha256`, `client_cert_pem`, `client_key_pem`, `device_name` | Trust and identity (above). |
| `launch_id` | `steam:<appid>` or `custom:<id>` to start a library title. |
| `profile_id` | The profile to play as; null lets the host choose. `rubyfunk_connection_profile` reads which it resolved. |
| `unlock` | A `RubyFunkProfileUnlock` for a profile on a person's own account: the password as typed, or a key proof signed over `rubyfunk_profile_unlock_message`. It goes only to a pinned host: without `pin_sha256` the connect fails with `INVALID_ARG`. The core copies the secret; wipe yours after the call. |
| `prompts_unlock` | 1 if you ask for the password and connect again after `REJECTED_PROFILE_LOCKED`. A non-null `unlock` implies it. |
| `timeout_ms` | Bounds the whole connect, including a wait for approval. |

The positional `rubyfunk_connect` to `rubyfunk_connect_ex12` stay for existing callers and are
frozen; new options land only in the struct.

After connect, build your decoder and presenter from what the host chose, never from your request:
`rubyfunk_connection_codec`, `_color_info` (CICP; transfer 16 or 18 is HDR), `_chroma_format`,
`_mode`, `_audio_channels`, `_audio_sample_rate`, `_audio_bits`, `_gamepad`, `_host_caps`.

## Video

`rubyfunk_connection_next_au` delivers complete access units in order, with parameter sets in
band. The first is an IDR; after that the stream is P-frames only. The core recovers from loss:
it freezes on the last good picture, asks the host for a repair, and asks again until one
decodes. Tell it what your decoder sees:

- Call `rubyfunk_connection_recovery_on_frame` for every AU before you decode it, in the order
  `next_au` returned them. Pass `complete = true`, and `decode_order = 0` unless your decoder
  numbers its decodes. When `out_admit` is false, drop the AU: it arrived behind one you already
  took and would rewind the decoder. `out_gap` is the number of frames lost ahead of it, and the
  `gap` that `rubyfunk_au_admission_note` takes.
- Call `rubyfunk_connection_recovery_on_decoded` for every picture the decoder returns, with its
  AU's `flags`. Pass `keyframe = false`, `RUBYFUNK_ANCHOR_EVIDENCE_UNAVAILABLE` and
  `decode_order = 0` unless your decoder reports them. When `out_hold` is true, keep the last good
  picture on screen and discard this one. `out_forgive` true tells a decoder that tracks damaged
  references to clear that record.
- Call `rubyfunk_connection_recovery_on_no_output` for an AU the decoder refused or returned
  nothing for. Call `rubyfunk_connection_recovery_lost` for a loss the frame index doesn't show:
  a wedged decoder, an AU you had to drop.
- Call `rubyfunk_connection_recovery_reset` when the decoder stops while the session lives: you
  rebuild it, or you drain AUs undecoded in the background. Without it the core keeps asking for a
  keyframe that nothing decodes.
- Call `rubyfunk_connection_request_keyframe` when your decoder needs an IDR: it lost its state,
  or it has no parameter sets yet. Once a decoder reports, the core sends one ask per 100 ms at
  most, so you can call it for every AU you can't decode.

The core watches for unrecoverable frames itself. `rubyfunk_connection_frames_dropped` is a
counter for a stats view.

`rubyfunk_connection_request_mode` switches resolution or refresh mid-session. When the host
accepts, the next AU is an IDR: rebuild the decoder from it.

## Audio

Use one of the two per connection. `rubyfunk_connection_next_audio_pcm` decodes in the core to
interleaved f32 (`FL FR FC LFE RL RR SL SR`); open your device at `_audio_sample_rate`.
`rubyfunk_connection_next_audio` hands you raw packets, for a client with a multistream Opus decoder.

## Input

Fill a `RubyFunkInputEvent` and call `rubyfunk_connection_send_input`. Fields depend on `kind`:

| Kind | Fields |
| --- | --- |
| `MOUSE_MOVE_ABS`, `TOUCH_DOWN`/`_MOVE` | `x`/`y` in pixels, `flags = (width << 16) \| height`. A zero `flags` is dropped. |
| `GAMEPAD_BUTTON` | `code` = `RUBYFUNK_BTN_*`, `x` ≠ 0 pressed, `flags` = pad index. |
| `GAMEPAD_AXIS` | `code` = `RUBYFUNK_AXIS_*`, `flags` = pad. Sticks are i16 with +y up; triggers 0–255. |
| `MOUSE_SCROLL` | `x` = signed delta, 120 per detent; `code` 0 vertical, 1 horizontal. |

Check `rubyfunk_connection_host_caps` before the capability-gated paths: `send_pen` needs
`RUBYFUNK_HOST_CAP_PEN`, `TEXT_INPUT` events need `RUBYFUNK_HOST_CAP_TEXT_INPUT`, and
`GAMEPAD_STATE` snapshots need `RUBYFUNK_HOST_CAP_GAMEPAD_STATE`. Other uplinks: `send_mic` (Opus
you encode), `send_rich_input2` (touchpads, motion), `send_hid_report` (raw reports for a
`RUBYFUNK_GAMEPAD_STEAMCONTROLLER2` pad).

## Feedback planes

| Pull | What you do with it |
| --- | --- |
| `next_rumble_cmd2` | Apply the motor levels; the core handles lease expiry. `next_rumble`, `_rumble2` and `_rumble_cmd` read the same plane, so use exactly one. |
| `next_hidout` | Replay lightbar, player LEDs, adaptive triggers or raw HID on the physical pad. |
| `next_hdr_meta` | Hand ST.2086 and content light level to your HDR display path. |
| `next_host_timing` | Split host and network latency in a stats view. |
| `next_cursor_shape` / `_state` | Draw the pointer. Only with `RUBYFUNK_CLIENT_CAP_CURSOR`. |

After `CLOSED`, `rubyfunk_connection_end_reason` says whether the session ended normally, and
`_end_reject` / `_end_reject_said` give the host's refusal and its sentence.

## Minimal example

Connects, pulls 600 access units, and quits.

```c
#include <stdio.h>
#include "rubyfunk_core.h"

int main(int argc, char **argv) {
    if (argc < 2 || rubyfunk_abi_version() != RUBYFUNK_ABI_VERSION) return 1;
    static char cert[4096], key[4096]; /* generate once, then load from storage */
    if (rubyfunk_generate_identity(cert, sizeof cert, key, sizeof key)) return 1;

    RubyFunkConnectOpts o = {0};
    o.struct_size = sizeof o;
    o.host = argv[1]; o.port = 9777;
    o.width = 1920; o.height = 1080; o.refresh_hz = 60;
    o.video_codecs = RUBYFUNK_CODEC_HEVC | RUBYFUNK_CODEC_H264;
    o.client_cert_pem = cert; o.client_key_pem = key; o.device_name = "My Client";
    o.timeout_ms = 180000; /* long enough to click Approve in the console */

    uint8_t host_fp[32]; int32_t status = 0;
    RubyFunkConnection *c = rubyfunk_connect_opts(&o, host_fp, &status);
    if (!c) { fprintf(stderr, "connect: status %d\n", status); return 1; }

    uint8_t codec = 0; rubyfunk_connection_codec(c, &codec);
    RubyFunkFrame f;
    for (int n = 0; n < 600;) {
        RubyFunkStatus rc = rubyfunk_connection_next_au(c, &f, 20);
        if (rc == RUBY_FUNK_STATUS_CLOSED) break;
        if (rc != RUBY_FUNK_STATUS_OK) continue;
        bool admit = true, hold = false;
        rubyfunk_connection_recovery_on_frame(c, f.frame_index, true, 0, &admit, NULL);
        if (!admit) continue; /* behind an AU already taken */
        /* feed f.data / f.len to a decoder for `codec`, then for the picture it returns: */
        rubyfunk_connection_recovery_on_decoded(
            c, f.flags, false, RUBYFUNK_ANCHOR_EVIDENCE_UNAVAILABLE, 0, &hold, NULL);
        /* show the picture unless `hold` */
        n++;
    }
    rubyfunk_connection_disconnect_quit(c);
    rubyfunk_connection_close(c);
    return 0;
}
```

A real client reports a refused AU and a stopped decoder too, persists the identity and
`host_fp`, and runs audio and feedback on their own threads. For a complete client over the same
API, read
[`crates/client/pf-client-core/src/session.rs`](https://git.unom.io/unom/punktfunk/src/branch/main/crates/client/pf-client-core/src/session.rs).
`bash crates/client/rubyfunk-ffi/tests/c/run.sh` proves the static library links from C on your machine.
