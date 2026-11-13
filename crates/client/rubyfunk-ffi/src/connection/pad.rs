//! Pads and pointer settings, and what the host sends back to the pads: controller
//! mouse, scroll direction, live pads, rumble and HID output.

#[cfg(feature = "quic")]
use crate::*;

/// Controller mouse is off: the pad plays. Equals `PadMouseMode::Off`.
pub const RUBYFUNK_PAD_MOUSE_OFF: u8 = 0;
/// The pad plays; its touchpads drive the pointer.
pub const RUBYFUNK_PAD_MOUSE_TOUCHPAD: u8 = 1;
/// The whole pad drives the pointer and a few keys; the host pad sits neutral.
pub const RUBYFUNK_PAD_MOUSE_FULL: u8 = 2;

/// Switch exactly the pads in `mask` (bit = wire pad index) to full controller mouse: their
/// buttons, sticks and touchpads drive the host pointer and a few keys while the host pad sits
/// neutral. Every other full-mouse pad returns to passthrough. Session-scoped. `Unsupported`
/// without `RUBYFUNK_GRANT_POINTER`.
///
/// # Safety
/// `c` is a valid connection handle. Callable from any thread.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_set_pad_mouse(
    c: *mut RubyFunkConnection,
    mask: u16,
) -> RubyFunkStatus {
    with_conn!(c => {
        status_of(c.inner.set_pad_mouse(mask))
    })
}

/// The controller-mouse mode every pad in `target` shares: `RUBYFUNK_PAD_MOUSE_OFF`, `_TOUCHPAD`
/// or `_FULL`. A mixed set reads as off.
///
/// # Safety
/// `c` is a valid connection handle; `mode` is writable (NULL is skipped).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_pad_mouse_mode(
    c: *const RubyFunkConnection,
    target: u16,
    mode: *mut u8,
) -> RubyFunkStatus {
    conn_out!(c, mode => c.inner.pad_mouse_mode(target) as u8)
}

/// Step the pads in `target` to the next controller-mouse mode (off, touchpad, full, off) and
/// write it to `mode`. In touchpad mode the pads stay in the game and their touchpads drive the
/// pointer. `Unsupported` without `RUBYFUNK_GRANT_POINTER`; `mode` is then left alone.
///
/// # Safety
/// `c` is a valid connection handle; `mode` is writable (NULL is skipped).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_cycle_pad_mouse(
    c: *mut RubyFunkConnection,
    target: u16,
    mode: *mut u8,
) -> RubyFunkStatus {
    with_conn!(c => {
        match c.inner.cycle_pad_mouse(target) {
            Ok(next) => {
                // SAFETY: the `# Safety` above makes `mode` null or writable for one byte.
                unsafe { put(mode, next as u8) };
                RubyFunkStatus::Ok
            }
            Err(e) => e.status(),
        }
    })
}

/// Change scroll direction for this session at the shared outbound seam.
///
/// # Safety
/// `c` is a valid connection handle. Callable from any thread.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_set_invert_scroll(
    c: *mut RubyFunkConnection,
    invert: bool,
) -> RubyFunkStatus {
    with_conn!(c => {
        c.inner.set_invert_scroll(invert);
        RubyFunkStatus::Ok
    })
}

/// Pads in controller mouse now. A removed pad or a lost pointer grant clears its bit.
///
/// # Safety
/// `c` is a valid connection handle; `mask` is writable (NULL is skipped).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_pad_mouse(
    c: *const RubyFunkConnection,
    mask: *mut u16,
) -> RubyFunkStatus {
    conn_out!(c, mask => c.inner.pad_mouse())
}

/// Wire pad indices the host holds now, a bit per pad: declared or driven, not yet removed.
///
/// # Safety
/// `c` is a valid connection handle; `mask` is writable (NULL is skipped).
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_live_pads(
    c: *const RubyFunkConnection,
    mask: *mut u16,
) -> RubyFunkStatus {
    conn_out!(c, mask => c.inner.live_pads())
}

/// Pull the next rumble update, waiting up to `timeout_ms`. Amplitudes are
/// 0..0xFFFF (`low`/`high` motors), `(0, 0)` = stop. Same timeout/closed as
/// [`rubyfunk_connection_next_audio`]. Drops the v2 self-terminating TTL —
/// use [`rubyfunk_connection_next_rumble2`] for the host-supplied lease.
///
/// # Safety
/// `c` is a valid connection handle; out pointers are writable (NULLs skipped).
/// At most one rumble puller; it may run concurrently with video/audio.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_next_rumble(
    c: *mut RubyFunkConnection,
    pad: *mut u16,
    low: *mut u16,
    high: *mut u16,
    timeout_ms: u32,
) -> RubyFunkStatus {
    // SAFETY: pointers forwarded unchanged; `next_rumble2` skips a null `ttl_ms`.
    unsafe { rubyfunk_connection_next_rumble2(c, pad, low, high, std::ptr::null_mut(), timeout_ms) }
}

/// `*ttl_ms` sentinel from [`rubyfunk_connection_next_rumble2`] when the host sent
/// no self-termination lease. Fall back to a client-side staleness heuristic.
pub const RUBYFUNK_RUMBLE_NO_TTL: u32 = 0xFFFF_FFFF;

/// Pull the next rumble update including its self-termination TTL. Same
/// `pad`/`low`/`high` as [`rubyfunk_connection_next_rumble`], plus `*ttl_ms`:
/// milliseconds to render this level unless the host renews. [`RUBYFUNK_RUMBLE_NO_TTL`]
/// = no lease; fall back to a client-side timeout. Reorder gate is applied inside.
///
/// # Safety
/// `c` is a valid connection handle; out pointers are writable (NULLs skipped).
/// At most one rumble puller; it may run concurrently with video/audio.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_next_rumble2(
    c: *mut RubyFunkConnection,
    pad: *mut u16,
    low: *mut u16,
    high: *mut u16,
    ttl_ms: *mut u32,
    timeout_ms: u32,
) -> RubyFunkStatus {
    with_conn!(c => {
        match c
            .inner
            .next_rumble_ttl(std::time::Duration::from_millis(timeout_ms as u64))
        {
            Ok((p, l, h, ttl)) => {
                // SAFETY: the caller passes each out-param null or writable for one value.
                unsafe {
                    put(pad, p);
                    put(low, l);
                    put(high, h);
                    put(ttl_ms, ttl.map_or(RUBYFUNK_RUMBLE_NO_TTL, u32::from));
                }
                RubyFunkStatus::Ok
            }
            Err(e) => e.status(),
        }
    })
}

/// `flags` bit for [`rubyfunk_connection_set_rumble_quirks`]: alternate the low
/// motor's LSB on keepalive re-emits so an SDL-class layer that no-ops identical
/// values still writes the device.
pub const RUBYFUNK_RUMBLE_QUIRK_DEDUP_JITTER: u32 = 1;

/// Effective rumble from the shared policy engine. No TTL: apply `(0, 0)` as
/// stop, else run at this level; `*backstop_ms` is a safety-net duration (`0` on
/// stop). Handle motors only — triggers are [`rubyfunk_connection_next_rumble_cmd2`].
/// Mutually exclusive with `next_rumble`/`next_rumble2`.
///
/// # Safety
/// `c` is a valid connection handle; out pointers are writable (NULLs skipped).
/// At most one rumble puller; it may run concurrently with video/audio.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_next_rumble_cmd(
    c: *mut RubyFunkConnection,
    pad: *mut u16,
    low: *mut u16,
    high: *mut u16,
    backstop_ms: *mut u32,
    timeout_ms: u32,
) -> RubyFunkStatus {
    // SAFETY: pointers forwarded unchanged; `next_rumble_cmd2` skips null trigger out-params.
    unsafe {
        rubyfunk_connection_next_rumble_cmd2(
            c,
            pad,
            low,
            high,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            backstop_ms,
            timeout_ms,
        )
    }
}

/// [`rubyfunk_connection_next_rumble_cmd`] plus Xbox impulse-trigger motors.
/// New symbol — growing the old signature would stack-corrupt old embedders.
/// Render triggers only on pads that have them; never fold into handles.
/// Same plane as `next_rumble_cmd`; call exactly one.
///
/// # Safety
/// `c` is a valid connection handle; out pointers are writable (NULLs skipped).
/// At most one rumble puller; it may run concurrently with video/audio.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_next_rumble_cmd2(
    c: *mut RubyFunkConnection,
    pad: *mut u16,
    low: *mut u16,
    high: *mut u16,
    left_trigger: *mut u16,
    right_trigger: *mut u16,
    backstop_ms: *mut u32,
    timeout_ms: u32,
) -> RubyFunkStatus {
    with_conn!(c => {
        match c
            .inner
            .next_rumble_command(std::time::Duration::from_millis(timeout_ms as u64))
        {
            Ok(cmd) => {
                // SAFETY: the caller passes each out-param null or writable for one value.
                unsafe {
                    put(pad, cmd.pad);
                    put(low, cmd.low);
                    put(high, cmd.high);
                    put(left_trigger, cmd.left_trigger);
                    put(right_trigger, cmd.right_trigger);
                    put(backstop_ms, cmd.backstop_ms);
                }
                RubyFunkStatus::Ok
            }
            Err(e) => e.status(),
        }
    })
}

/// Per-pad rumble quirks (call at attach). `keepalive_ms`: re-emit non-zero
/// (Steam Deck ≈ 40); `0` = none. `min_pulse_ms`: floor for `backstop_ms`.
/// A renderer that dedupes its own writes cannot use `keepalive_ms`.
///
/// # Safety
/// `c` is a valid connection handle. Callable from any thread.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_set_rumble_quirks(
    c: *mut RubyFunkConnection,
    pad: u16,
    keepalive_ms: u16,
    min_pulse_ms: u16,
    flags: u32,
) -> RubyFunkStatus {
    with_conn!(c => {
        c.inner.set_rumble_quirks(
            pad,
            rubyfunk_core::client::ActuatorQuirks {
                keepalive_ms,
                min_pulse_ms,
                dedup_jitter: flags & RUBYFUNK_RUMBLE_QUIRK_DEDUP_JITTER != 0,
            },
        );
        RubyFunkStatus::Ok
    })
}

/// Pull the next HID-output feedback (DualSense lightbar / player LEDs / adaptive
/// trigger, or SC2 `RUBYFUNK_HIDOUT_HID_RAW`) into `*out`.
/// [`RubyFunkStatus::NoFrame`] on timeout, [`RubyFunkStatus::Closed`] once ended.
/// DualSense and SC2 backends only. One puller, may run alongside other planes.
///
/// # Safety
/// `c` is a valid connection handle; `out` is writable for one `RubyFunkHidOutput`.
#[cfg(feature = "quic")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rubyfunk_connection_next_hidout(
    c: *mut RubyFunkConnection,
    out: *mut RubyFunkHidOutput,
    timeout_ms: u32,
) -> RubyFunkStatus {
    with_conn!(c => {
        if out.is_null() {
            return RubyFunkStatus::NullPointer;
        }
        match c
            .inner
            .next_hidout(std::time::Duration::from_millis(timeout_ms as u64))
        {
            Ok(h) => {
                // SAFETY: `out` is non-null on this path; written once by value.
                unsafe { *out = RubyFunkHidOutput::from_hid(&h) };
                RubyFunkStatus::Ok
            }
            Err(e) => e.status(),
        }
    })
}

#[cfg(test)]
mod tests {
    use rubyfunk_core::input::PadMouseMode;

    #[test]
    fn pad_mouse_constants_are_the_core_modes() {
        for (c, mode) in [
            (super::RUBYFUNK_PAD_MOUSE_OFF, PadMouseMode::Off),
            (super::RUBYFUNK_PAD_MOUSE_TOUCHPAD, PadMouseMode::Touchpad),
            (super::RUBYFUNK_PAD_MOUSE_FULL, PadMouseMode::Full),
        ] {
            assert_eq!(PadMouseMode::from_u8(c), Some(mode));
        }
    }
}
