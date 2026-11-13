//! WDK link flags for the cdylib (wdk-build) + `IddCxStub` (the driver calls IddCx DDIs via wdk-iddcx,
//! and exports `IddMinimumVersionRequired`). `/INTEGRITYCHECK` (set by wdk-build) is cleared by the CI
//! packaging step.
fn main() -> Result<(), wdk_build::ConfigError> {
    wdk_build::configure_wdk_binary_build()?;
    link_iddcx_stub();
    Ok(())
}

/// The stub's dispatch table must match the IddCx headers. Compare versions numerically:
/// `1.10` sorts before `1.2` as text. The configured WDK and installed kits supply libraries.
fn link_iddcx_stub() {
    println!("cargo:rerun-if-env-changed=WDKContentRoot");
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").expect("CARGO_CFG_TARGET_ARCH");
    let cpu = wdk_build::CpuArchitecture::try_from_cargo_str(&target_arch)
        .unwrap_or_else(|| panic!("no WDK lib dir for target arch {target_arch}"));
    let arch = cpu.as_windows_str();
    const ROOTS: [&str; 2] = [
        r"C:\Program Files (x86)\Windows Kits\10\Lib",
        r"C:\Program Files\Windows Kits\10\Lib",
    ];
    let roots = std::env::var_os("WDKContentRoot")
        .map(|root| std::path::PathBuf::from(root).join("Lib"))
        .into_iter()
        .chain(ROOTS.into_iter().map(std::path::PathBuf::from));
    let mut best: Option<((u32, u32), std::path::PathBuf)> = None;
    for root in roots {
        let Ok(versions) = std::fs::read_dir(root) else {
            continue;
        };
        for ver in versions.flatten() {
            let iddcx = ver.path().join("um").join(arch).join("iddcx");
            let Ok(subdirs) = std::fs::read_dir(&iddcx) else {
                continue;
            };
            for sub in subdirs.flatten() {
                if !sub.path().join("IddCxStub.lib").is_file() {
                    continue;
                }
                let name = sub.file_name().to_string_lossy().into_owned();
                let mut parts = name.split('.');
                let v = (
                    parts.next().and_then(|x| x.parse().ok()).unwrap_or(0u32),
                    parts.next().and_then(|x| x.parse().ok()).unwrap_or(0u32),
                );
                if best.as_ref().is_none_or(|(bv, _)| v > *bv) {
                    best = Some((v, sub.path()));
                }
            }
        }
    }
    let Some((_, dir)) = best else {
        panic!(
            "IddCxStub.lib not found under any Windows Kits Lib\\<ver>\\um\\{arch}\\iddcx\\<iddcxver>\\"
        );
    };
    println!("cargo:rustc-link-search={}", dir.display());
    println!("cargo:rustc-link-lib=static=IddCxStub");
}
