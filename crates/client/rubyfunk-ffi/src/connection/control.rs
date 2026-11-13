//! Steering a live session: compositor and bitrate, clock offset, mode, keyframe and
//! RFI requests, frame accounting, the stats HUD, decode-latency reports, the speed
//! test and teardown.

#[cfg(feature = "quic")]
use crate::*;

/// Compositor the host resolved (`RUBYFUNK_COMPOSITOR_*`; Welcome echo of
/// [`rubyfunk_connect_ex`]). `AUTO` = a host that didn't say. Gamescope PipeWire
/// capture carries no cursor — default to a client-side cursor there.
///
/// # Safety
/// `c` is a valid connection handle; `compositor` is writable (NULL is skipped).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_compositor(
    c: *const RubyFunkConnection,
    compositor: *mut u32,
) -> RubyFunkStatus {
    conn_out!(c, compositor => c.inner.resolved_compositor.to_u8() as u32)
}

/// Video encoder bitrate (kbps) the host configured — the [`rubyfunk_connect_ex3`]
/// request clamped to the host range, or its default when `0` was requested.
/// `0` = a host that didn't report it. Safe any time after connect.
///
/// # Safety
/// `c` is a valid connection handle; `bitrate_kbps` is writable (NULL is skipped).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_bitrate(
    c: *const RubyFunkConnection,
    bitrate_kbps: *mut u32,
) -> RubyFunkStatus {
    conn_out!(c, bitrate_kbps => c.inner.resolved_bitrate_kbps)
}

/// Connect-time wall-clock offset, ns, host minus client. Add to a local
/// realtime stamp to express it in the host capture clock (`pts_ns`). `0` = none.
///
/// # Safety
/// `c` is a valid connection handle; `offset_ns` is writable (NULL is skipped).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_clock_offset_ns(
    c: *const RubyFunkConnection,
    offset_ns: *mut i64,
) -> RubyFunkStatus {
    conn_out!(c, offset_ns => c.inner.clock_offset_ns)
}

/// Live wall-clock offset (updated by mid-stream re-sync). Use this for ongoing
/// latency math, not the frozen connect-time value.
///
/// # Safety
/// `c` is a valid connection handle; `offset_ns` is writable (NULL is skipped).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_clock_offset_now_ns(
    c: *const RubyFunkConnection,
    offset_ns: *mut i64,
) -> RubyFunkStatus {
    conn_out!(c, offset_ns => c.inner.clock_offset_now_ns())
}

/// Request a live mode switch. On accept, the first new-mode AU is an IDR with
/// in-band parameter sets — rebuild the decoder from it.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_request_mode(
    c: *const RubyFunkConnection,
    width: u32,
    height: u32,
    refresh_hz: u32,
) -> RubyFunkStatus {
    with_conn!(c => {
        status_of(c.inner.request_mode(rubyfunk_core::config::Mode {
            width,
            height,
            refresh_hz,
        }))
    })
}

/// The decoder needs an IDR; infinite GOP sends none unasked. With a decoder reporting
/// through `rubyfunk_connection_recovery_*` the core arms the freeze and sends one ask per
/// 100 ms window. Before the first report, and after a reset, the ask goes at once: throttle.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_request_keyframe(
    c: *const RubyFunkConnection,
) -> RubyFunkStatus {
    with_conn!(c => {
        status_of(c.inner.request_keyframe())
    })
}

/// The device's network path changed: call from the platform's path monitor when an
/// interface comes up, goes down or takes over the default route. The host then follows
/// a roam within a round trip instead of the next keep-alive.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_path_changed(
    c: *const RubyFunkConnection,
) -> RubyFunkStatus {
    with_conn!(c => {
        c.inner.path_changed();
        RubyFunkStatus::Ok
    })
}

/// Ask the host to recover `[first_frame, last_frame]` by RFI (P-frame tagged
/// `USER_FLAG_RECOVERY_ANCHOR`) instead of a full IDR. Throttle; keyframe is the backstop.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_request_rfi(
    c: *const RubyFunkConnection,
    first_frame: u32,
    last_frame: u32,
) -> RubyFunkStatus {
    with_conn!(c => {
        status_of(c.inner.request_rfi(first_frame, last_frame))
    })
}

/// [`rubyfunk_connection_recovery_on_decoded`]'s `evidence`: the lane has no parser.
pub const RUBYFUNK_ANCHOR_EVIDENCE_UNAVAILABLE: u32 = 0;
/// The picture predicts only from references that decoded clean.
pub const RUBYFUNK_ANCHOR_EVIDENCE_CLEAN: u32 = 1;
/// The picture predicts from a concealed one: its anchor flag does not lift the freeze.
pub const RUBYFUNK_ANCHOR_EVIDENCE_DAMAGED: u32 = 2;

/// Report one AU before decode, in receive order; a sliced AU once, on its first part. On a
/// gap the core arms the freeze and asks the host for the lost range. `out_admit` false:
/// drop the AU, a straggler a reference decoder rewinds on or a partial a newer frame beat.
/// `out_gap` is the frames lost ahead of it, the `gap` [`rubyfunk_au_admission_note`]
/// takes. `complete` false is a partial delivery. `decode_order` is the decoder's count so
/// far, 0 where it numbers none.
///
/// # Safety
/// `c` is a valid connection handle; the out pointers are writable or NULL.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_recovery_on_frame(
    c: *const RubyFunkConnection,
    index: u32,
    complete: bool,
    decode_order: u64,
    out_admit: *mut bool,
    out_gap: *mut u32,
) -> RubyFunkStatus {
    with_conn!(c => {
        let arrival = c.inner.recovery_on_au(index, complete, decode_order);
        // SAFETY: caller out-params, each null or writable for one value.
        unsafe {
            put(out_admit, arrival.admit);
            put(out_gap, arrival.gap);
        }
        RubyFunkStatus::Ok
    })
}

/// Report one decoded picture. `out_hold` true: keep the last good picture on glass
/// instead of this one. `flags` are the AU's wire flags; `keyframe` is the decoder's own
/// IDR bit, false where it flags none; `evidence` is a `RUBYFUNK_ANCHOR_EVIDENCE_*`;
/// `decode_order` is this picture's decode count from 1, 0 where the decoder numbers none.
/// `out_forgive` true: the freeze lifted on an intra-refresh heal, so a reference-chain
/// ledger forgets its damage marks. An unknown `evidence` returns
/// [`RubyFunkStatus::InvalidArg`].
///
/// # Safety
/// `c` is a valid connection handle; the out pointers are writable or NULL.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_recovery_on_decoded(
    c: *const RubyFunkConnection,
    flags: u32,
    keyframe: bool,
    evidence: u32,
    decode_order: u64,
    out_hold: *mut bool,
    out_forgive: *mut bool,
) -> RubyFunkStatus {
    use rubyfunk_core::reanchor::{AnchorEvidence, LocalRecovery};
    with_conn!(c => {
        let evidence = match evidence {
            RUBYFUNK_ANCHOR_EVIDENCE_UNAVAILABLE => AnchorEvidence::Unavailable,
            RUBYFUNK_ANCHOR_EVIDENCE_CLEAN => AnchorEvidence::ReferencesClean,
            RUBYFUNK_ANCHOR_EVIDENCE_DAMAGED => AnchorEvidence::ReferencesDamaged,
            _ => return RubyFunkStatus::InvalidArg,
        };
        let shown = c.inner.recovery_on_decoded(rubyfunk_core::client::Decoded {
            flags,
            keyframe,
            evidence,
            local: LocalRecovery::NONE,
            decode_order: (decode_order != 0).then_some(decode_order),
        });
        // SAFETY: caller out-params, each null or writable for one value.
        unsafe {
            put(out_hold, shown.hold);
            put(out_forgive, shown.forgive_chain);
        }
        RubyFunkStatus::Ok
    })
}

/// An AU produced no picture. Three in a row arm the freeze and ask for a keyframe.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_recovery_on_no_output(
    c: *const RubyFunkConnection,
) -> RubyFunkStatus {
    with_conn!(c => {
        c.inner.recovery_on_no_output();
        RubyFunkStatus::Ok
    })
}

/// A loss the frame index cannot show, such as a wedged decoder: arms the freeze and asks
/// for a keyframe.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_recovery_lost(
    c: *const RubyFunkConnection,
) -> RubyFunkStatus {
    with_conn!(c => {
        c.inner.recovery_lost();
        RubyFunkStatus::Ok
    })
}

/// The decoder is gone or parked (a restart, a background drain): drops the freeze.
/// Nothing asks until the next report, which starts a fresh one. Call it while draining
/// AUs undecoded: a freeze nothing reports to asks for a keyframe every half second.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_recovery_reset(
    c: *const RubyFunkConnection,
) -> RubyFunkStatus {
    with_conn!(c => {
        c.inner.recovery_reset();
        RubyFunkStatus::Ok
    })
}

/// Unrecoverable reassembler drops. For a client that reports through
/// `rubyfunk_connection_recovery_*` the core watches it: a climb past a gap's credit
/// freezes and asks for a keyframe. Writes 0 on NULL.
///
/// # Safety
/// `c` is a valid connection handle; `out` is writable (NULL is skipped).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_frames_dropped(
    c: *const RubyFunkConnection,
    out: *mut u64,
) -> RubyFunkStatus {
    guard(|| {
        // Write 0 on a NULL connection before the handle check (header contract).
        // SAFETY: the caller passes `out` null or writable for one value.
        unsafe { put(out, 0) };
        // SAFETY: caller handle or null; `as_mut`/`as_ref` never dereference null.
        let c = match unsafe { c.as_ref() } {
            Some(c) => c,
            None => return RubyFunkStatus::NullPointer,
        };
        // SAFETY: the caller passes `out` null or writable for one value.
        unsafe { put(out, c.inner.frames_dropped()) };
        RubyFunkStatus::Ok
    })
}

/// Facts only the embedder knows, for [`rubyfunk_connection_hud_text`]. Zero-init, set
/// `struct_size = sizeof(RubyFunkHudFacts)`, then the fields you mean. Append only; bump ABI.
#[cfg(feature = "quic")]
#[repr(C)]
#[derive(Clone, Copy)]
pub struct RubyFunkHudFacts {
    /// `sizeof(RubyFunkHudFacts)` as this caller was compiled.
    pub struct_size: u32,
    /// The displayed stamps are true on-glass instants.
    pub on_glass: bool,
    /// Take the measured OS present floor off end-to-end and display (iOS, tvOS).
    pub shave_os_floor: bool,
    /// Decoded audio queued ahead of the speaker, ms, for an embedder that plays audio itself.
    /// `0` keeps the core's reading.
    pub audio_buffer_ms: u32,
    /// Where that buffer puts audio against the picture, ms; positive = audio behind.
    pub av_offset_ms: i32,
    /// NUL-terminated preset name, or null.
    pub preset: *const c_char,
    /// Embedder-only Advanced Detailed lines, `<role>\t<text>\n` each, or null.
    pub extras: *const c_char,
}

#[cfg(all(feature = "quic", target_pointer_width = "64"))]
const _: () = assert!(core::mem::size_of::<RubyFunkHudFacts>() == 32);

/// [`rubyfunk_connection_hud_text`]'s facts applied to a drained window.
///
/// # Safety
/// `facts` is null or points to at least its declared `struct_size` bytes, and its strings are
/// NUL-terminated or null.
#[cfg(feature = "quic")]
unsafe fn hud_with_facts(
    mut s: rubyfunk_core::hud::StatsSnapshot,
    facts: *const RubyFunkHudFacts,
) -> Result<rubyfunk_core::hud::StatsSnapshot, RubyFunkStatus> {
    if facts.is_null() {
        return Ok(s);
    }
    // SAFETY: `addr_of!` does not form a `&`; a shorter layout is rejected before the full read.
    let declared = unsafe { std::ptr::addr_of!((*facts).struct_size).read_unaligned() } as usize;
    if declared < std::mem::size_of::<RubyFunkHudFacts>() {
        return Err(RubyFunkStatus::InvalidArg);
    }
    // SAFETY: non-null, and `struct_size` covers this type. Fields are read one at a time and
    // the bools as bytes, so a binding that stores 2 cannot produce an invalid `bool`.
    let (on_glass, shave_os_floor, audio_buffer_ms, av_offset_ms, preset, extras) = unsafe {
        use std::ptr::addr_of;
        (
            addr_of!((*facts).on_glass).cast::<u8>().read_unaligned() != 0,
            addr_of!((*facts).shave_os_floor)
                .cast::<u8>()
                .read_unaligned()
                != 0,
            addr_of!((*facts).audio_buffer_ms).read_unaligned(),
            addr_of!((*facts).av_offset_ms).read_unaligned(),
            addr_of!((*facts).preset).read_unaligned(),
            addr_of!((*facts).extras).read_unaligned(),
        )
    };
    s.on_glass = on_glass;
    s.shave_os_floor = shave_os_floor;
    if audio_buffer_ms > 0 {
        s.audio_buffer_ms = audio_buffer_ms;
        s.av_offset_ms = av_offset_ms;
    }
    // SAFETY: caller strings, NUL-terminated or null, borrowed for this call.
    let preset = unsafe { opt_cstr(preset) }.map_err(|()| RubyFunkStatus::InvalidArg)?;
    s.preset = preset.filter(|p| !p.is_empty()).map(str::to_owned);
    // SAFETY: as above.
    let extras = unsafe { opt_cstr(extras) }.map_err(|()| RubyFunkStatus::InvalidArg)?;
    s.extras
        .extend(extras.unwrap_or_default().lines().filter_map(|line| {
            let (code, text) = line.split_once('\t')?;
            Some(rubyfunk_core::hud::Extra {
                text: text.to_owned(),
                tier: rubyfunk_core::hud::StatsVerbosity::Detailed,
                advanced_only: true,
                role: rubyfunk_core::hud::Role::from_code(code.parse().ok()?),
            })
        }));
    Ok(s)
}

/// Stats overlay: one frame left the decoder. `pts_ns` is its capture stamp; `received_ns` (the
/// AU's reassembly stamp) and `decoded_ns` are client `CLOCK_REALTIME`. A zero `received_ns`
/// counts the frame without a decode sample.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_hud_decoded(
    c: *const RubyFunkConnection,
    pts_ns: u64,
    received_ns: u64,
    decoded_ns: u64,
) -> RubyFunkStatus {
    with_conn!(c => {
        let hud = c.inner.hud();
        hud.note_decoded(pts_ns, decoded_ns);
        if received_ns > 0 && decoded_ns >= received_ns {
            hud.note_decode_us((decoded_ns - received_ns) / 1000, false);
        }
        RubyFunkStatus::Ok
    })
}

/// Stats overlay: one frame reached the screen at `displayed_ns`, client `CLOCK_REALTIME`.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_hud_displayed(
    c: *const RubyFunkConnection,
    pts_ns: u64,
    decoded_ns: u64,
    displayed_ns: u64,
) -> RubyFunkStatus {
    with_conn!(c => {
        c.inner
            .hud()
            .note_displayed(pts_ns, decoded_ns, 0, displayed_ns);
        RubyFunkStatus::Ok
    })
}

/// Stats overlay: one sample of the OS present pipeline's depth, ns: how far ahead of glass the
/// compositor takes a frame. Shaved off the shown figures when the facts ask for it.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_hud_os_floor(
    c: *const RubyFunkConnection,
    floor_ns: u64,
) -> RubyFunkStatus {
    with_conn!(c => {
        c.inner.hud().note_os_floor_us(floor_ns / 1000);
        RubyFunkStatus::Ok
    })
}

/// Close the stats overlay's window, about once a second. [`rubyfunk_connection_hud_text`]
/// formats what this kept as often as the tier changes.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_hud_drain(
    c: *const RubyFunkConnection,
) -> RubyFunkStatus {
    with_conn!(c => {
        *lock_recover(&c.hud_snap) = c.inner.hud_snapshot();
        RubyFunkStatus::Ok
    })
}

/// The last drained window as overlay lines, `<role>\t<text>\n` each (role 0 primary, 1 detail,
/// 2 muted, 3 warning), NUL-terminated into `out`. `tier` is 0 off to 3 detailed; `advanced`
/// picks the Advanced vocabulary; `facts` may be null. When `cap` is too small nothing is
/// written and the status is `InvalidArg`; `*needed` (when non-null) always holds the size.
///
/// # Safety
/// `c` is a valid connection handle; `out` is writable for `cap` bytes; `facts` is null or
/// valid per [`RubyFunkHudFacts`]; `needed` is null or writable.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_hud_text(
    c: *const RubyFunkConnection,
    tier: u32,
    advanced: bool,
    facts: *const RubyFunkHudFacts,
    out: *mut c_char,
    cap: usize,
    needed: *mut usize,
) -> RubyFunkStatus {
    with_conn!(c => {
        let snap = lock_recover(&c.hud_snap).clone();
        // SAFETY: the caller's `facts` contract, checked inside.
        let snap = match unsafe { hud_with_facts(snap, facts) } {
            Ok(s) => s,
            Err(status) => return status,
        };
        let tier = rubyfunk_core::hud::StatsVerbosity::from_index(tier);
        let text = rubyfunk_core::hud::encode_lines(&rubyfunk_core::hud::format(&snap, tier, advanced));
        // SAFETY: the caller passes `needed` null or writable for one value.
        unsafe { put(needed, text.len() + 1) };
        // SAFETY: `out` is null or writable for `cap` bytes, per this function's contract.
        if !unsafe { write_cstr(out, cap, &text) } {
            return RubyFunkStatus::InvalidArg;
        }
        RubyFunkStatus::Ok
    })
}

/// Decode-stage latency in µs: AU leave [`next_au`] to decoded output. Include
/// decoder-input backlog; exclude vsync wait. Feeds Automatic bitrate. Skip if
/// [`rubyfunk_connection_wants_decode_latency`] is false.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_report_decode_us(
    c: *const RubyFunkConnection,
    us: u32,
) -> RubyFunkStatus {
    with_conn!(c => {
        c.inner.report_decode_us(us);
        RubyFunkStatus::Ok
    })
}

/// Whether [`rubyfunk_connection_report_decode_us`] is worth calling: writes true
/// only when Automatic bitrate is armed (non-PyroWave). Skip the per-frame
/// measurement otherwise. Constant for the session. Writes false on a NULL connection.
///
/// # Safety
/// `c` is a valid connection handle; `out` is writable (NULL is skipped).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_wants_decode_latency(
    c: *const RubyFunkConnection,
    out: *mut bool,
) -> RubyFunkStatus {
    guard(|| {
        // Write false on a NULL connection before the handle check (uninitialized is not a bool).
        // SAFETY: the caller passes `out` null or writable for one value.
        unsafe { put(out, false) };
        // SAFETY: caller handle or null; `as_mut`/`as_ref` never dereference null.
        let c = match unsafe { c.as_ref() } {
            Some(c) => c,
            None => return RubyFunkStatus::NullPointer,
        };
        // SAFETY: the caller passes `out` null or writable for one value.
        unsafe { put(out, c.inner.wants_decode_latency()) };
        RubyFunkStatus::Ok
    })
}

/// Speed-test measurement from [`rubyfunk_connection_probe_result`]. `done` is 0
/// until the host's end-of-burst report, then 1. `throughput_kbps` is delivered
/// wire throughput; `loss_pct` is link loss; `host_drop_pct` is send-buffer drop
/// (raise `net.core.wmem_max`). Measured separately so a host that can't keep up
/// reads differently from a lossy link.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct RubyFunkProbeResult {
    /// 1 once the host's end-of-burst report arrived (measurement final); else 0 (partial).
    pub done: u8,
    /// Delivered wire bytes (header + shard) / packets the client received during the burst.
    pub recv_bytes: u64,
    pub recv_packets: u32,
    /// Application goodput bytes / access units the host offered.
    pub host_bytes: u64,
    pub host_packets: u32,
    /// Throughput denominator, ms: client-measured burst receive interval, live
    /// while bursting and final once `done`; host send-window duration when fewer
    /// than two probe packets arrived. Host duration alone overstates throughput —
    /// its window closes while the bottleneck queue is still draining.
    pub elapsed_ms: u32,
    /// Delivered wire throughput = `recv_bytes * 8 / elapsed_ms` (kilobits/second).
    pub throughput_kbps: u32,
    /// Link loss `(wire_packets_sent − recv_packets) / wire_packets_sent` as a percentage.
    pub loss_pct: f32,
    /// Host-side send-buffer drop `send_dropped / (wire_packets_sent + send_dropped)`, percent.
    pub host_drop_pct: f32,
    /// Wire packets the host put on the link, and the ones its send buffer dropped.
    pub wire_packets_sent: u32,
    pub send_dropped: u32,
    /// Probe inter-arrival gap, µs, to a tenth of a millisecond: median and 99th percentile.
    /// Their difference is the path's jitter.
    pub gap_p50_us: u32,
    pub gap_p99_us: u32,
    /// Probe packets that arrived behind a later one.
    pub reorders: u32,
}

/// Start a bandwidth speed test: host bursts filler at `target_kbps` goodput for
/// `duration_ms` (clamped ≤ 10 Gbps / ≤ 5 s), briefly pausing video. Non-blocking —
/// poll [`rubyfunk_connection_probe_result`] until `done` is 1. Starting a probe
/// resets any prior measurement.
///
/// # Safety
/// `c` is a valid connection handle.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_speed_test(
    c: *const RubyFunkConnection,
    target_kbps: u32,
    duration_ms: u32,
) -> RubyFunkStatus {
    with_conn!(c => {
        status_of(c.inner.request_probe(target_kbps, duration_ms))
    })
}

/// Read the current speed-test measurement into `*out` (partial until `out->done == 1`).
/// Safe to poll after [`rubyfunk_connection_speed_test`]; before any probe it reports zeros.
///
/// # Safety
/// `c` is a valid connection handle; `out` is writable for one `RubyFunkProbeResult`
/// (NULL is an error).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_probe_result(
    c: *const RubyFunkConnection,
    out: *mut RubyFunkProbeResult,
) -> RubyFunkStatus {
    with_conn!(c => {
        if out.is_null() {
            return RubyFunkStatus::NullPointer;
        }
        let o = c.inner.probe_result();
        // SAFETY: `out` is a caller-owned `#[repr(C)]` slot, written once by value.
        unsafe {
            *out = RubyFunkProbeResult {
                done: o.done as u8,
                recv_bytes: o.recv_bytes,
                recv_packets: o.recv_packets,
                host_bytes: o.host_bytes,
                host_packets: o.host_packets,
                elapsed_ms: o.elapsed_ms,
                throughput_kbps: o.throughput_kbps,
                loss_pct: o.loss_pct,
                host_drop_pct: o.host_drop_pct,
                wire_packets_sent: o.wire_packets_sent,
                send_dropped: o.send_dropped,
                gap_p50_us: o.gap_p50_us,
                gap_p99_us: o.gap_p99_us,
                reorders: o.reorders,
            };
        }
        RubyFunkStatus::Ok
    })
}

/// One finding of the network check: the id names the text the app shows
/// ([`rubyfunk_core::client::health::FindingId`] as a byte), `numbers` are its figures.
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct RubyFunkHealthFinding {
    pub id: u8,
    pub severity: u8,
    pub numbers: [u32; 3],
}

/// Most findings one report carries; the rules can produce seven.
pub const RUBYFUNK_HEALTH_FINDINGS_MAX: usize = 8;

/// The network check's report ([`rubyfunk_core::client::health::HealthReport`]), flat.
/// `has_clean` 0 = a host without a ramp (no loss figure is honest); a leg or fact that was
/// not sampled reads `0`.
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct RubyFunkHealthReport {
    pub ceiling_kbps: u32,
    pub wall: u8,
    pub has_clean: u8,
    pub clean_rate_kbps: u32,
    pub clean_loss_pct: f32,
    pub clean_jitter_us: u32,
    pub client_iface_kind: u8,
    pub client_link_mbps: u32,
    pub client_rcvbuf_kb: u32,
    pub host_iface_kind: u8,
    pub host_link_mbps: u32,
    pub host_sndbuf_kb: u32,
    /// Loss of the bursts leg and the capped leg, percent; `n_legs` says how many ran.
    pub n_legs: u8,
    pub leg_loss_pct: [f32; 2],
    pub n_findings: u8,
    pub findings: [RubyFunkHealthFinding; RUBYFUNK_HEALTH_FINDINGS_MAX],
}

/// Run the network check over this connection and write its report into `*out`. Blocking
/// for ten to twenty seconds — call it off the main thread. The connection should have been
/// dialled for probes only (`delivery_flags` `2`). Errors: `Unsupported` when the host
/// declined, `Timeout` when a round never reported.
///
/// # Safety
/// `c` is a valid connection handle; `out` is writable for one `RubyFunkHealthReport`
/// (NULL is an error).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_network_check(
    c: *const RubyFunkConnection,
    out: *mut RubyFunkHealthReport,
) -> RubyFunkStatus {
    use rubyfunk_core::client::health::{self, LegShape, SpeedError};
    with_conn!(c => {
        if out.is_null() {
            return RubyFunkStatus::NullPointer;
        }
        let r = match health::health_check(&c.inner, |_| {}) {
            Ok(r) => r,
            Err(SpeedError::Request(e)) => return status_of(Err::<(), _>(e)),
            Err(SpeedError::Declined) => return RubyFunkStatus::Unsupported,
            Err(SpeedError::Timeout) => return RubyFunkStatus::Timeout,
        };
        let mut rep = RubyFunkHealthReport {
            ceiling_kbps: r.speed.ceiling_kbps,
            wall: r.speed.wall as u8,
            client_iface_kind: r.client.link.kind,
            client_link_mbps: r.client.link.mbps,
            client_rcvbuf_kb: r.client.rcvbuf_kb,
            host_iface_kind: r.host.iface_kind,
            host_link_mbps: r.host.link_mbps,
            host_sndbuf_kb: r.host.sndbuf_kb,
            ..Default::default()
        };
        if let Some(cl) = r.speed.clean {
            rep.has_clean = 1;
            rep.clean_rate_kbps = cl.rate_kbps;
            rep.clean_loss_pct = cl.loss_pct;
            rep.clean_jitter_us = cl.jitter_us;
        }
        for leg in &r.legs {
            let slot = match leg.shape {
                LegShape::FrameBursts => 0,
                LegShape::Capped => 1,
            };
            rep.leg_loss_pct[slot] = leg.outcome.loss_pct;
            rep.n_legs = rep.n_legs.max(slot as u8 + 1);
        }
        for (slot, f) in r.findings.iter().take(RUBYFUNK_HEALTH_FINDINGS_MAX).enumerate() {
            rep.findings[slot] = RubyFunkHealthFinding {
                id: f.id as u8,
                severity: f.severity as u8,
                numbers: f.numbers,
            };
            rep.n_findings = slot as u8 + 1;
        }
        // SAFETY: `out` is a caller-owned `#[repr(C)]` slot, written once by value.
        unsafe { *out = rep };
        RubyFunkStatus::Ok
    })
}

/// Signal a deliberate quit (user stop, not a network drop) before closing: the
/// connection closes with [`QUIT_CLOSE_CODE`] instead of 0, so the host skips the
/// keep-alive linger. Call before [`rubyfunk_connection_close`] on a user disconnect;
/// a plain close leaves the linger intact. NULL is a no-op.
///
/// # Safety
/// `c` was returned by [`rubyfunk_connect`] and remains valid until `rubyfunk_connection_close`.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_disconnect_quit(c: *mut RubyFunkConnection) {
    guard_void(|| {
        // SAFETY: caller handle or null; `as_mut`/`as_ref` never dereference null.
        if let Some(c) = unsafe { c.as_ref() } {
            c.inner.disconnect_quit();
        }
    });
}

/// Close the connection and free the handle (joins the internal threads). NULL is a no-op.
///
/// # Safety
/// `c` was returned by [`rubyfunk_connect`] and is not used after this call.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_close(c: *mut RubyFunkConnection) {
    guard_void(|| {
        if !c.is_null() {
            // SAFETY: pointers are caller-supplied and null-checked on this path.
            drop(unsafe { Box::from_raw(c) });
        }
    });
}

#[cfg(all(test, feature = "quic"))]
mod tests {
    use super::*;

    /// The facts land on the snapshot; a short `struct_size` is a status, not a read.
    #[cfg(feature = "quic")]
    #[test]
    fn hud_facts_apply_to_a_drained_window() {
        let preset = std::ffi::CString::new("Work").unwrap();
        let extras =
            std::ffi::CString::new("2\tlink latency ask 1.00\nno tab\n3\tclock\n").unwrap();
        // SAFETY: an all-zero struct is a valid value (null pointers, zero scalars).
        let mut f: RubyFunkHudFacts = unsafe { std::mem::zeroed() };
        f.struct_size = std::mem::size_of::<RubyFunkHudFacts>() as u32;
        f.on_glass = true;
        f.shave_os_floor = true;
        f.audio_buffer_ms = 28;
        f.av_offset_ms = -3;
        f.preset = preset.as_ptr();
        f.extras = extras.as_ptr();
        // SAFETY: `f` and its strings outlive the call.
        let s = unsafe { hud_with_facts(Default::default(), &f) }.unwrap();
        assert!(s.on_glass && s.shave_os_floor);
        assert_eq!((s.audio_buffer_ms, s.av_offset_ms), (28, -3));
        assert_eq!(s.preset.as_deref(), Some("Work"));
        assert_eq!(s.extras.len(), 2);
        assert_eq!(s.extras[1].role, rubyfunk_core::hud::Role::Warn);
        assert!(s.extras.iter().all(|e| e.advanced_only));
        f.struct_size = 8;
        // SAFETY: as above; the short size is the documented rejected case.
        let short = unsafe { hud_with_facts(Default::default(), &f) };
        assert_eq!(short.unwrap_err(), RubyFunkStatus::InvalidArg);
        // SAFETY: null facts are the documented no-op.
        assert!(unsafe { hud_with_facts(Default::default(), std::ptr::null()) }.is_ok());

        // A non-C binding may store 2 in a bool byte; that reads as true, not as UB (Miri).
        f.struct_size = std::mem::size_of::<RubyFunkHudFacts>() as u32;
        let mut bytes = [0u8; std::mem::size_of::<RubyFunkHudFacts>()];
        // SAFETY: a byte copy of an initialised `f` into a buffer of the same size.
        unsafe {
            std::ptr::copy_nonoverlapping(
                (&raw const f).cast::<u8>(),
                bytes.as_mut_ptr(),
                bytes.len(),
            )
        };
        bytes[std::mem::offset_of!(RubyFunkHudFacts, on_glass)] = 2;
        // SAFETY: `bytes` holds `struct_size` readable bytes; the strings outlive the call.
        let s = unsafe { hud_with_facts(Default::default(), bytes.as_ptr().cast()) }.unwrap();
        assert!(s.on_glass);
    }

    #[cfg(feature = "quic")]
    #[test]
    fn hud_calls_report_a_null_connection() {
        let null = std::ptr::null();
        let mut buf = [0 as std::os::raw::c_char; 8];
        // SAFETY: null handles are the documented reported-not-UB case.
        let statuses = unsafe {
            [
                rubyfunk_connection_hud_decoded(null, 1, 1, 2),
                rubyfunk_connection_hud_displayed(null, 1, 2, 3),
                rubyfunk_connection_hud_os_floor(null, 1),
                rubyfunk_connection_hud_drain(null),
                rubyfunk_connection_hud_text(
                    null,
                    3,
                    true,
                    std::ptr::null(),
                    buf.as_mut_ptr(),
                    buf.len(),
                    std::ptr::null_mut(),
                ),
            ]
        };
        assert!(statuses.iter().all(|s| *s == RubyFunkStatus::NullPointer));
    }

    /// A null connection is a status, and the out-params keep what the caller put there.
    #[cfg(feature = "quic")]
    #[test]
    fn recovery_calls_report_a_null_connection() {
        let null = std::ptr::null();
        let (mut admit, mut gap, mut hold) = (true, 7u32, true);
        // SAFETY: null handles are the documented reported-not-UB case; the outs are live.
        let statuses = unsafe {
            [
                rubyfunk_connection_recovery_on_frame(null, 1, true, 0, &mut admit, &mut gap),
                rubyfunk_connection_recovery_on_decoded(
                    null,
                    0,
                    false,
                    RUBYFUNK_ANCHOR_EVIDENCE_UNAVAILABLE,
                    0,
                    &mut hold,
                    std::ptr::null_mut(),
                ),
                rubyfunk_connection_recovery_on_no_output(null),
                rubyfunk_connection_recovery_lost(null),
                rubyfunk_connection_recovery_reset(null),
            ]
        };
        assert!(statuses.iter().all(|s| *s == RubyFunkStatus::NullPointer));
        assert_eq!((admit, gap, hold), (true, 7, true));
    }
}
