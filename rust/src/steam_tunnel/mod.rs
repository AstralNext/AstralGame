//! Steam(SDR) 组网实现（仅 Windows）。
//!
//! 由 `api::steam` 在 Windows 分支调用，替代 EasyTier 实例作为「网络驱动层」：
//! 自己用 wintun 建虚拟网卡，把 IPv4 包经 Steam Datagram Relay 送到房间成员，
//! 组成星型虚拟局域网。
//!
//! 模块划分：
//! - [`proto`]     帧/控制/RPC 编解码与 IP 工具
//! - [`tun`]       wintun 网卡与收发线程
//! - `engine`      单线程引擎（Steam 回调泵 + 房间 + 数据面 + 应用 RPC）

mod engine;
pub(crate) mod proto;
pub(crate) mod tun;

pub(crate) use engine::{
    app_call, app_notify, app_reply, my_peer_id, peer_ping, room_info, start, status, stop,
    subscribe_app_inbound, subscribe_status,
};
