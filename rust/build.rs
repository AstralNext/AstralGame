// 解决 Windows 链 EasyTier 时报 `LNK1181: cannot open input file 'Packet.lib'`：
//
// EasyTier 的 build.rs 用 `cargo:rustc-link-search=native=easytier/third_party/...` 这
// 一**相对路径**指向自己仓库里自带的 `Packet.lib`。当 EasyTier 是顶层 workspace 时
// 这条相对路径能命中；但当 EasyTier 作为 git 依赖被 `astral_rust_core` 引用时，链接
// 器的工作目录变成我们的 build 目录，那条相对路径不存在 → 链接失败。
//
// 解决思路与 EasyTier 一致：在自己 crate 内置一份 `Packet.lib`（覆盖 x86_64 / i686 /
// arm64），在 `build.rs` 里用 `CARGO_MANIFEST_DIR` 拼成**绝对路径**加进 link search。
// 这样 CI、第三方 build 都不再需要安装 Npcap SDK；本地若设了 `NPCAP_SDK_DIR`，
// 仍允许覆盖到自定义 SDK 目录。
fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }

    println!("cargo:rerun-if-env-changed=NPCAP_SDK_DIR");
    if let Ok(sdk) = std::env::var("NPCAP_SDK_DIR") {
        // 用户显式指定外部 Npcap SDK，优先使用。
        println!("cargo:rustc-link-search=native={}", sdk);
        return;
    }

    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR not set during build");
    let arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
    let arch_dir = match arch.as_str() {
        "x86_64" => "x86_64",
        "x86" => "i686",
        "aarch64" => "arm64",
        other => {
            println!(
                "cargo:warning=unsupported windows target_arch `{}`, skipping bundled Npcap libs",
                other
            );
            return;
        }
    };

    let lib_dir = std::path::PathBuf::from(&manifest_dir)
        .join("third_party")
        .join(arch_dir);
    if !lib_dir.exists() {
        println!(
            "cargo:warning=bundled third_party dir not found: {}",
            lib_dir.display()
        );
        return;
    }
    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rerun-if-changed={}", lib_dir.join("Packet.lib").display());
}
