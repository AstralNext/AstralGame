pub mod api;
mod frb_generated;
mod lan_nat;
// Steam 组网实现放在 `api` 之外：flutter_rust_bridge 只扫描 `crate::api`，
// 这样内部的帧协议 / wintun 类型不会被导出成 Dart 类。
#[cfg(target_os = "windows")]
pub(crate) mod steam_tunnel;
// Holepunch Pear(HyperDHT) 组网：复用 Steam 的帧协议与 wintun 网卡，
// 连接层由 Node 侧车（pear/pear_tunnel.mjs）提供。
#[cfg(target_os = "windows")]
pub(crate) mod pear_tunnel;
// Keep this file changing when the vendored EasyTier checkout is patched,
// so cargokit's crate hash invalidates and Cargo rebuilds the dependency.
