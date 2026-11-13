//! Compiles `tests/c/harness.c`, links it to a freshly built native static library,
//! and asserts a lossy-loopback frame round-trip. Canonical path is `tests/c/run.sh`;
//! this mirrors it so `cargo test` alone covers the C boundary.

use std::path::{Path, PathBuf};
use std::process::Command;

/// System libraries required by the Rust static library. The compiler supplies
/// the platform C runtime. See `rustc --print native-static-libs`.
fn native_libs() -> &'static [&'static str] {
    if cfg!(target_os = "macos") {
        // Workspace `quic` pulls rustls's platform verifier (Security/CoreFoundation). libopus
        // is bundled into the staticlib.
        &[
            "-liconv",
            "-lm",
            "-framework",
            "Security",
            "-framework",
            "CoreFoundation",
        ]
    } else if cfg!(target_os = "linux") {
        // libopus is bundled into the staticlib and needs `-lm`.
        &["-lgcc_s", "-lutil", "-lrt", "-lpthread", "-lm", "-ldl"]
    } else if cfg!(target_env = "msvc") {
        &[
            "-ladvapi32",
            "-lbcrypt",
            "-lcrypt32",
            "-ldbghelp",
            "-liphlpapi",
            "-lkernel32",
            "-lncrypt",
            "-lntdll",
            "-lole32",
            "-lsecur32",
            "-luserenv",
            "-lws2_32",
        ]
    } else {
        &[]
    }
}

fn ensure_staticlib(profile_dir: &Path) -> PathBuf {
    // A separate target keeps the nested feature build from invalidating the outer
    // test's rlibs. The C header and static library both require QUIC.
    let nested = profile_dir
        .parent()
        .expect("target dir")
        .join("c-abi-harness");
    let cargo = std::env::var("CARGO").unwrap_or_else(|_| "cargo".into());
    let built = Command::new(cargo)
        .args([
            "build",
            "--locked",
            "-p",
            "punktfunk-ffi",
            "--features",
            "quic",
        ])
        .env("CARGO_TARGET_DIR", &nested)
        .status()
        .expect("build C harness static library");
    assert!(
        built.success(),
        "C harness static library build did not complete"
    );
    let name = if cfg!(target_env = "msvc") {
        "punktfunk_ffi.lib"
    } else {
        "libpunktfunk_ffi.a"
    };
    nested.join("debug").join(name)
}

#[test]
fn c_abi_harness_round_trips() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let harness = manifest.join("tests/c/harness.c");
    let include = manifest.join("../../../include");

    let exe = std::env::current_exe().expect("current_exe");
    // current_exe is `.../target/<profile>/deps/c_abi-<hash>`; two parents is the profile dir.
    let profile_dir = exe
        .parent()
        .and_then(Path::parent)
        .expect("profile dir")
        .to_path_buf();

    let staticlib = ensure_staticlib(&profile_dir);
    assert!(
        staticlib.exists(),
        "staticlib not found at {} (run `cargo build -p punktfunk-ffi`)",
        staticlib.display()
    );
    assert!(
        include.join("punktfunk_core.h").exists(),
        "generated header missing; run `cargo run -p gen-headers`"
    );

    let cc = std::env::var("CC").unwrap_or_else(|_| {
        if cfg!(target_env = "msvc") {
            "clang"
        } else {
            "cc"
        }
        .into()
    });
    let out = profile_dir.join(format!(
        "punktfunk_c_harness{}",
        std::env::consts::EXE_SUFFIX
    ));

    let mut compile = Command::new(&cc);
    compile
        // Match `ensure_staticlib`'s `quic` build so the harness can use that header surface.
        .args([
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-O2",
            "-DPUNKTFUNK_FEATURE_QUIC",
            "-I",
        ])
        .arg(&include);
    compile
        .arg(&harness)
        .arg(&staticlib)
        .args(native_libs())
        .arg("-o")
        .arg(&out);

    match compile.status() {
        Ok(s) => assert!(s.success(), "C harness failed to compile/link"),
        Err(e) => {
            // No C toolchain. Skip rather than fail the suite; `tests/c/run.sh` covers CI.
            eprintln!("skipping C ABI test: cannot invoke `{cc}`: {e}");
            return;
        }
    }

    let run = Command::new(&out).status().expect("run C harness");
    assert!(run.success(), "C harness reported a round-trip failure");
}
