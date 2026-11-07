//! Steam(SDR) 组网模式（Windows 专属）。
//!
//! 与 EasyTier 组网模式并存，由 Dart 侧「联机模式」开关决定用哪一个：
//! EasyTier 负责常规虚拟局域网；这里用 wintun + Steam Datagram Relay 自建
//! 星型虚拟局域网（房主转发），作为 EasyTier 的替代「网络驱动层」。
//!
//! 设计要点：
//! - 单条 P2P 连接（虚拟端口 `0xA57A`）同时承载 IP 包、控制消息与应用 RPC；
//! - 房主 `100.100.100.1`，客人 `.2` 起按顺序分配；不设默认网关；
//! - 局域网发现只走 TUN 内广播/组播泛洪，不做物理网卡旁路；
//! - Steam API 是进程级单例且非 Send，全部收在一个后台线程里，8ms tick 驱动。
//!
//! 这里只是跨平台门面：Windows 下转发到私有子模块 `steam_tunnel`，其余平台返回
//! 「不支持」，这样 Android / Linux / macOS 构建不会引入 Steam SDK。

/// Steam 运行状态（登录 / SteamID / SDR 中继 / 当前房间）。
#[derive(Clone)]
pub struct SteamStatusInfo {
    pub ok: bool,
    pub logged_on: bool,
    pub steam_id: String,
    pub persona: String,
    pub relay_ready: bool,
    /// 是否已加入 / 创建组网房间。
    pub room_active: bool,
    /// 本机是否为房主。
    pub is_host: bool,
    /// 本机虚拟 IP（未组网时为空）。
    pub virtual_ip: String,
    /// 房间内成员数（含自己）。
    pub member_count: u32,
    pub message: String,
}

impl Default for SteamStatusInfo {
    fn default() -> Self {
        Self {
            ok: false,
            logged_on: false,
            steam_id: String::new(),
            persona: String::new(),
            relay_ready: false,
            room_active: false,
            is_host: false,
            virtual_ip: String::new(),
            member_count: 0,
            message: "正在连接 Steam…".to_string(),
        }
    }
}

/// 房间成员快照。
#[derive(Clone)]
pub struct SteamMemberInfo {
    pub peer_id: u32,
    pub steam_id: String,
    pub nickname: String,
    pub virtual_ip: String,
    pub latency_ms: u32,
    pub online: bool,
    pub is_host: bool,
    pub is_self: bool,
    /// Steam 连接是否经中继转发（false = 直连）。
    pub via_relay: bool,
    pub bytes_in: u64,
    pub bytes_out: u64,
}

/// 一条 Steam 大厅搜索结果 / 当前大厅。
#[derive(Clone, Default)]
pub struct SteamLobbyInfo {
    /// Steam 大厅 id（十进制字符串，避免 64 位精度问题）。
    pub lobby_id: String,
    /// `ag_game`：游戏标识（构建房间时手动选择）。
    pub game_id: String,
    /// `ag_name`：房间展示名。
    pub name: String,
    /// `ag_gate`：`basic` / `double` / `open`。
    pub gate: String,
    /// `ag_ver`：组网协议版本。
    pub version: String,
    /// 房主 SteamID。
    pub host_steam_id: String,
    pub players: u32,
    pub capacity: u32,
    pub joinable: bool,
}

/// 组网诊断快照：双机验收时用来确认大厅与隔离字段的真实值。
#[derive(Clone, Default)]
pub struct SteamLobbyDiag {
    /// 当前大厅 id；未建房时为空。
    pub lobby_id: String,
    /// 从 Steam 大厅 data 读回的 `ag_game` 实际值。
    pub game_id: String,
    /// 从 Steam 大厅 data 读回的 `ag_ver` 实际值。
    pub version: String,
    /// 从 Steam 大厅 data 读回的 `ag_gate` 实际值。
    pub gate: String,
    pub joinable: bool,
    pub members: u32,
    pub capacity: u32,
    /// 是否房主。
    pub is_host: bool,
    /// Steam 覆盖层是否开启（决定原生邀请面板是否可用）。
    pub overlay_enabled: bool,
    /// 本次房间内是否真正调用过 `activate_invite_dialog`。
    pub invite_dialog_called: bool,
    /// 覆盖层不可用时的说明；可用时为空。
    pub overlay_hint: String,
}

/// 当前 Steam 组网房间信息。
#[derive(Clone, Default)]
pub struct SteamRoomInfo {
    pub active: bool,
    pub is_host: bool,
    pub virtual_ip: String,
    /// 虚拟网段（如 `100.100.100.0/24`）。
    pub network: String,
    pub member_count: u32,
    pub self_peer_id: u32,
    pub members: Vec<SteamMemberInfo>,
}

use crate::frb_generated::StreamSink;
#[cfg(target_os = "windows")]
use crate::steam_tunnel;

#[cfg(not(target_os = "windows"))]
fn unsupported() -> String {
    "Steam 组网仅支持 Windows 桌面端".to_string()
}

/// 读取当前 Steam 状态；首次调用会拉起后台线程。
pub fn steam_status() -> SteamStatusInfo {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::status()
    }
    #[cfg(not(target_os = "windows"))]
    {
        SteamStatusInfo {
            message: unsupported(),
            ..Default::default()
        }
    }
}

/// 订阅 Steam 状态变化（登录 / SDR 就绪 / 房间）；订阅时立即推送当前快照。
#[allow(unused_variables)]
pub fn steam_subscribe_status(sink: StreamSink<SteamStatusInfo>) {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::subscribe_status(sink);
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = sink.add(SteamStatusInfo {
            message: unsupported(),
            ..Default::default()
        });
    }
}

/// 读取当前 Steam 组网房间信息（成员 / 虚拟 IP / 延迟）。
pub fn steam_room_info() -> SteamRoomInfo {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::room_info()
    }
    #[cfg(not(target_os = "windows"))]
    {
        SteamRoomInfo::default()
    }
}

/// 启动 Steam 组网。[host] 为真表示房主，否则加入 [host_steam_id] 的房间。
///
/// [join_token] 是房间口令（复用 inviter 里的 networkSecret）：房主在 Hello 中校验。
#[allow(unused_variables)]
pub async fn steam_start(
    host: bool,
    host_steam_id: String,
    join_token: String,
    nickname: String,
    game_id: String,
) -> Result<SteamStatusInfo, String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::start(host, host_steam_id, join_token, nickname, game_id).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (host, host_steam_id, join_token, nickname, game_id);
        Err(unsupported())
    }
}

/// 创建 Steam 公开大厅并直接开房（写 `ag_*` 标签、开启 P2P 监听）。
#[allow(clippy::too_many_arguments)]
pub async fn steam_lobby_create(
    game_id: String,
    name: String,
    gate: String,
    max_members: u32,
    join_token: String,
    nickname: String,
) -> Result<SteamLobbyInfo, String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::create_lobby(game_id, name, gate, max_members, join_token, nickname).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (game_id, name, gate, max_members, join_token, nickname);
        Err(unsupported())
    }
}

/// 搜索本游戏的大厅（服务端 `ag_game` 过滤 + 本地二次校验）。
pub async fn steam_lobby_search(game_id: String) -> Result<Vec<SteamLobbyInfo>, String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::search(game_id).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = game_id;
        Err(unsupported())
    }
}

/// 加入大厅并连上房主；返回时隧道已可用。
pub async fn steam_lobby_join(
    lobby_id: String,
    game_id: String,
    join_token: String,
    nickname: String,
) -> Result<SteamLobbyInfo, String> {
    #[cfg(target_os = "windows")]
    {
        let id = lobby_id
            .trim()
            .parse::<u64>()
            .map_err(|_| "无效的大厅 ID".to_string())?;
        steam_tunnel::join_lobby(id, game_id, join_token, nickname).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (lobby_id, game_id, join_token, nickname);
        Err(unsupported())
    }
}

/// 诊断用：往成员表注入一个「离线超过宽限期」的成员，跑一次真实 prune，
/// 返回摘除前后的成员数。需要 `ASTRAL_STEAM_DEBUG=1` 且当前是房主。
pub async fn steam_debug_ghost_probe() -> Result<String, String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::debug_ghost_probe().await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 只读大厅元数据（加入后立刻离开），用于邀请进房前确认门槛。
pub async fn steam_lobby_peek(lobby_id: String) -> Result<SteamLobbyInfo, String> {
    #[cfg(target_os = "windows")]
    {
        let id = lobby_id
            .trim()
            .parse::<u64>()
            .map_err(|_| "无效的大厅 ID".to_string())?;
        steam_tunnel::peek_lobby(id).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = lobby_id;
        Err(unsupported())
    }
}

/// 离开当前大厅（同时停止隧道）。
pub async fn steam_lobby_leave() -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::leave_lobby().await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Ok(())
    }
}

/// 设置大厅是否可被搜索到（关房前先置 false）。
pub async fn steam_lobby_set_joinable(joinable: bool) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::set_lobby_joinable(joinable).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = joinable;
        Ok(())
    }
}

/// 打开 Steam 原生好友邀请界面。
///
/// 覆盖层被禁用时不会静默调用，直接返回可展示给用户的失败原因。
pub async fn steam_lobby_invite_dialog() -> Result<String, String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::invite_dialog().await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 直接邀请指定好友进入当前大厅（不依赖覆盖层）。
///
/// 返回成功文案只代表 Steam 受理了请求，不代表对方已收到或接受。
pub async fn steam_lobby_invite_friend(friend_steam_id: String) -> Result<String, String> {
    #[cfg(target_os = "windows")]
    {
        let friend = friend_steam_id
            .trim()
            .parse::<u64>()
            .map_err(|_| "无效的 SteamID".to_string())?;
        steam_tunnel::invite_friend(friend).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = friend_steam_id;
        Err(unsupported())
    }
}

/// 组网诊断：大厅 id、`ag_*` 实际值、可加入状态、人数与覆盖层状态。
pub async fn steam_lobby_diag() -> Result<SteamLobbyDiag, String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::lobby_diag().await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 诊断用：把引擎切到客人分支，注入一个「房主已离线超过宽限期」的成员并跑
/// 真实 `prune`，验证客人侧宽限过滤。需要 `ASTRAL_STEAM_DEBUG=1`。
pub async fn steam_debug_guest_roster_probe() -> Result<String, String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::debug_guest_roster_probe().await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 读取待处理的好友邀请大厅 id（Dart 侧轮询）。
pub fn steam_pending_lobby_invite() -> Option<String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::peer_pending_lobby_invite()
    }
    #[cfg(not(target_os = "windows"))]
    {
        None
    }
}

/// 清空待处理的邀请（进房成功或用户放弃后调用）。
pub fn steam_clear_pending_lobby_invite() {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::clear_pending_lobby_invite();
    }
}

/// 停止 Steam 组网（保留 Steam 进程级连接）。
pub fn steam_stop() -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::stop()
    }
    #[cfg(not(target_os = "windows"))]
    {
        Ok(())
    }
}

/// 本机在 Steam 房间内的 peer_id（0 表示未组网）。
pub fn steam_my_peer_id() -> u32 {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::my_peer_id()
    }
    #[cfg(not(target_os = "windows"))]
    {
        0
    }
}

/// 应用内 RPC：调用远端方法并等待回包。
#[allow(unused_variables)]
pub async fn steam_app_call(
    dst_peer_id: u32,
    channel: String,
    request_id: u64,
    payload: Vec<u8>,
    flags: u32,
    timeout_ms: i32,
) -> Result<crate::api::p2p::AppCallResultC, String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::app_call(dst_peer_id, channel, request_id, payload, flags, timeout_ms).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 应用内 RPC：通知（fire-and-forget）。
#[allow(unused_variables)]
pub async fn steam_app_notify(
    dst_peer_id: u32,
    channel: String,
    payload: Vec<u8>,
) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::app_notify(dst_peer_id, channel, payload).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 应用内 RPC：回复一条入站 Call。
#[allow(unused_variables)]
pub async fn steam_app_call_reply(
    token: u64,
    status: i32,
    error_msg: String,
    payload: Vec<u8>,
) -> Result<bool, String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::app_reply(token, status, error_msg, payload).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 应用内 RPC：往返测延迟（毫秒）。
#[allow(unused_variables)]
pub async fn steam_peer_ping(dst_peer_id: u32, timeout_ms: i32) -> Result<i64, String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::peer_ping(dst_peer_id, timeout_ms).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}

/// 订阅入站应用 RPC 事件。
#[allow(unused_variables)]
pub async fn steam_subscribe_app_inbound(
    sink: crate::frb_generated::StreamSink<crate::api::p2p::AppInboundEventC>,
) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        steam_tunnel::subscribe_app_inbound(sink);
        Ok(())
    }
    #[cfg(not(target_os = "windows"))]
    {
        Err(unsupported())
    }
}
