//! Holepunch Pear(HyperDHT) 组网门面（Windows 专属）。
//!
//! 与 Steam 组网并存，由 Dart 侧「联机模式」选择。底层连接由 `pear/pear_tunnel.mjs`
//! 侧车提供：房主在 HyperDHT 上发布服务端（打洞失败时自动走 Holepunch 中继），
//! 成员按房主公钥连接；虚拟网卡、成员表、虚拟 IP 与帧转发仍由 Rust 引擎完成，
//! 协议与 Steam 组网共用 [`crate::steam_tunnel::proto`]。

/// Pear 运行状态。
#[derive(Clone, Debug)]
pub struct PearStatusInfo {
    /// 运行时（Node + 侧车脚本）是否可用。
    pub ok: bool,
    /// HyperDHT / 侧车链路是否已就绪。
    pub ready: bool,
    /// 房主公钥（房主为本机公钥，成员为对方房主公钥）。
    pub host_key: String,
    pub nickname: String,
    /// 是否已加入 / 创建组网房间。
    pub room_active: bool,
    pub is_host: bool,
    /// 本机虚拟 IP（未组网时为空）。
    pub virtual_ip: String,
    /// 房间内成员数（含自己）。
    pub member_count: u32,
    pub message: String,
}

impl Default for PearStatusInfo {
    fn default() -> Self {
        Self {
            ok: false,
            ready: false,
            host_key: String::new(),
            nickname: String::new(),
            room_active: false,
            is_host: false,
            virtual_ip: String::new(),
            member_count: 0,
            message: "Pear 未初始化".to_string(),
        }
    }
}

/// 房间成员快照。
#[derive(Clone, Debug)]
pub struct PearMemberInfo {
    pub peer_id: u32,
    pub pear_key: String,
    pub nickname: String,
    pub virtual_ip: String,
    pub latency_ms: u32,
    pub online: bool,
    pub is_host: bool,
    pub is_self: bool,
    pub bytes_in: u64,
    pub bytes_out: u64,
}

/// 当前 Pear 组网房间信息。
#[derive(Clone, Default, Debug)]
pub struct PearRoomInfo {
    pub active: bool,
    pub is_host: bool,
    pub virtual_ip: String,
    /// 虚拟网段（如 `100.100.100.0/24`）。
    pub network: String,
    pub member_count: u32,
    pub self_peer_id: u32,
    pub members: Vec<PearMemberInfo>,
}

#[cfg(target_os = "windows")]
use crate::pear_tunnel;

#[cfg(not(target_os = "windows"))]
fn unsupported() -> String {
    "Pear 组网仅支持 Windows 桌面端".to_string()
}

/// 读取当前 Pear 状态；首次调用会拉起后台线程。
pub fn pear_status() -> PearStatusInfo {
    #[cfg(target_os = "windows")]
    {
        pear_tunnel::status()
    }
    #[cfg(not(target_os = "windows"))]
    {
        PearStatusInfo {
            message: unsupported(),
            ..Default::default()
        }
    }
}

/// 读取当前 Pear 组网房间信息。
pub fn pear_room_info() -> PearRoomInfo {
    #[cfg(target_os = "windows")]
    {
        pear_tunnel::room_info()
    }
    #[cfg(not(target_os = "windows"))]
    {
        PearRoomInfo::default()
    }
}

/// 启动 Pear 组网。[host] 为真表示房主；否则按 [host_key]（房主公钥十六进制）加入。
pub async fn pear_start(
    host: bool,
    host_key: String,
    join_token: String,
    nickname: String,
) -> Result<PearStatusInfo, String> {
    #[cfg(target_os = "windows")]
    {
        pear_tunnel::start(host, host_key, join_token, nickname).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (host, host_key, join_token, nickname);
        Err(unsupported())
    }
}

/// 停止 Pear 组网（关闭侧车进程与虚拟网卡）。
pub fn pear_stop() -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        pear_tunnel::stop()
    }
    #[cfg(not(target_os = "windows"))]
    {
        Ok(())
    }
}

/// 本机在 Pear 房间内的 peer_id（0 表示未组网）。
pub fn pear_my_peer_id() -> u32 {
    #[cfg(target_os = "windows")]
    {
        pear_tunnel::my_peer_id()
    }
    #[cfg(not(target_os = "windows"))]
    {
        0
    }
}

/// 应用内 RPC：调用远端方法并等待回包。
#[allow(unused_variables)]
pub async fn pear_app_call(
    dst_peer_id: u32,
    channel: String,
    request_id: u64,
    payload: Vec<u8>,
    flags: u32,
    timeout_ms: i32,
) -> Result<crate::api::p2p::AppCallResultC, String> {
    #[cfg(target_os = "windows")]
    {
        pear_tunnel::app_call(dst_peer_id, channel, request_id, payload, flags, timeout_ms).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 应用内 RPC：通知（fire-and-forget）。
#[allow(unused_variables)]
pub async fn pear_app_notify(
    dst_peer_id: u32,
    channel: String,
    payload: Vec<u8>,
) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        pear_tunnel::app_notify(dst_peer_id, channel, payload).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 应用内 RPC：回复一条入站 Call。
#[allow(unused_variables)]
pub async fn pear_app_call_reply(
    token: u64,
    status: i32,
    error_msg: String,
    payload: Vec<u8>,
) -> Result<bool, String> {
    #[cfg(target_os = "windows")]
    {
        pear_tunnel::app_reply(token, status, error_msg, payload).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 应用内 RPC：往返测延迟（毫秒）。
#[allow(unused_variables)]
pub async fn pear_peer_ping(dst_peer_id: u32, timeout_ms: i32) -> Result<i64, String> {
    #[cfg(target_os = "windows")]
    {
        pear_tunnel::peer_ping(dst_peer_id, timeout_ms).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 订阅入站应用 RPC 事件。
#[allow(unused_variables)]
pub async fn pear_subscribe_app_inbound(
    sink: crate::frb_generated::StreamSink<crate::api::p2p::AppInboundEventC>,
) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        pear_tunnel::subscribe_app_inbound(sink);
        Ok(())
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}
