//! The Apple client's one static library: the rubyfunk C ABI, linked whole, plus the
//! console's (`rubyfunk_console_*`). Swift imports both as `RubyFunkCore`.

pub use rubyfunk_ffi;

#[cfg(target_vendor = "apple")]
mod console;
