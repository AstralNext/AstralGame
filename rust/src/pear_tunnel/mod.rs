//! Holepunch Pear(HyperDHT) 组网实现（仅 Windows）。
//!
//! 连接层交给 Node 侧车（`pear/pear_tunnel.mjs`，依赖 hyperdht）：
//! 房主在 DHT 上发布服务端，成员按房主公钥连接；打洞失败时由 Holepunch
//! 的 DHT 中继节点转发。Rust 侧负责虚拟网卡、成员表 / 虚拟 IP、帧转发与
//! 应用内 RPC，协议与 Steam 组网共用 [`crate::steam_tunnel::proto`]。

mod engine;

pub(crate) use engine::{
    app_call, app_notify, app_reply, my_peer_id, peer_ping, room_info, start, status, stop,
    subscribe_app_inbound,
};
