//! Steam 组网引擎：单线程持有 Steam Client、wintun 会话与全部 NetConnection。
//!
//! 拓扑（第一版）：星型。房主监听 P2P 端口，客人连房主；IP 包与 RPC 都经房主转发。
//! 所有 Steam 调用都集中在引擎线程，靠 8ms tick（空闲 40ms）驱动回调泵与数据面。

use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::net::Ipv4Addr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};

use lazy_static::lazy_static;
use steamworks::networking_sockets::{ListenSocket, NetConnection, NetworkingSockets};
use steamworks::networking_types::{
    ListenSocketEvent, NetworkingAvailability, NetworkingConnectionState, NetworkingIdentity,
    SendFlags,
};
use steamworks::{
    AppId, CallbackHandle, Client, GameLobbyJoinRequested, GameRichPresenceJoinRequested, LobbyId,
    LobbyKey, LobbyListFilter, LobbyType, Matchmaking, SteamId, SteamServersConnected,
    SteamServersDisconnected, StringFilter, StringFilterKind,
};
use tokio::sync::oneshot;

use super::lobby::{self, Gate, LobbySnapshot};
use super::proto::{self, Frame, RosterEntry};
use super::roster_policy::{self, MemberView};
use super::tun::{self, TunRoom};
use crate::api::p2p::{AppCallResultC, AppInboundEventC, AppInboundKindC};
use crate::api::steam::{
    SteamLobbyDiag, SteamLobbyInfo, SteamMemberInfo, SteamRoomInfo, SteamStatusInfo,
};
use crate::frb_generated::StreamSink;

/// 初始化失败后的重试间隔：避免设置页轮询把失败刷成忙等。
const BOOT_RETRY: Duration = Duration::from_secs(5);
/// 客人等待 Welcome 的上限。
const START_TIMEOUT: Duration = Duration::from_secs(15);
/// 心跳周期。
const HEARTBEAT: Duration = Duration::from_secs(3);
/// 广播去重窗口。
const DEDUP_WINDOW: Duration = Duration::from_secs(2);
/// 重连间隔。
const RECONNECT_DELAY: Duration = Duration::from_secs(3);
const CONTROL_VPORT_CACHE: i32 = proto::VPORT;
/// 单次大厅操作（创建 / 搜索 / 加入）的上限。
const LOBBY_TIMEOUT: Duration = Duration::from_secs(20);
/// 大厅默认人数上限。
const DEFAULT_LOBBY_CAP: u32 = 8;

enum Cmd {
    Start {
        host: bool,
        host_steam_id: String,
        join_token: String,
        nickname: String,
        game_id: String,
        reply: oneshot::Sender<Result<SteamRoomInfo, String>>,
    },
    LobbyCreate {
        game_id: String,
        name: String,
        gate: String,
        max_members: u32,
        join_token: String,
        nickname: String,
        reply: oneshot::Sender<Result<SteamLobbyInfo, String>>,
    },
    LobbySearch {
        game_id: String,
        reply: oneshot::Sender<Result<Vec<SteamLobbyInfo>, String>>,
    },
    LobbyJoin {
        lobby_id: u64,
        game_id: String,
        join_token: String,
        nickname: String,
        reply: oneshot::Sender<Result<SteamLobbyInfo, String>>,
    },
    /// 只读大厅元数据：加入后立刻离开，用于邀请进房前确认门槛。
    LobbyPeek {
        lobby_id: u64,
        reply: oneshot::Sender<Result<SteamLobbyInfo, String>>,
    },
    /// 诊断用：注入一个「早已离线」的成员，跑一次真实 prune。
    DebugGhost {
        reply: oneshot::Sender<Result<String, String>>,
    },
    /// 诊断用：切到客人分支，注入离线超宽限期的房主并跑真实 prune。
    DebugGuestRoster {
        reply: oneshot::Sender<Result<String, String>>,
    },
    LobbyLeave {
        reply: oneshot::Sender<Result<(), String>>,
    },
    LobbySetJoinable {
        joinable: bool,
        reply: oneshot::Sender<Result<(), String>>,
    },
    LobbyInviteDialog {
        reply: oneshot::Sender<Result<String, String>>,
    },
    /// 直接邀请指定好友进大厅（不依赖覆盖层）。
    LobbyInviteFriend {
        friend_steam_id: u64,
        reply: oneshot::Sender<Result<String, String>>,
    },
    /// 组网诊断快照。
    LobbyDiag {
        reply: oneshot::Sender<Result<SteamLobbyDiag, String>>,
    },
    Stop,
    AppCall {
        dst_peer_id: u32,
        channel: String,
        request_id: u64,
        payload: Vec<u8>,
        flags: u32,
        reply: oneshot::Sender<Result<AppCallResultC, String>>,
    },
    AppNotify {
        dst_peer_id: u32,
        channel: String,
        payload: Vec<u8>,
        reply: oneshot::Sender<Result<(), String>>,
    },
    AppReply {
        token: u64,
        status: i32,
        error_msg: String,
        payload: Vec<u8>,
        reply: oneshot::Sender<bool>,
    },
    PeerPing {
        dst_peer_id: u32,
        reply: oneshot::Sender<Result<u64, String>>,
    },
}

lazy_static! {
    static ref TX: Mutex<Option<Sender<Cmd>>> = Mutex::new(None);
    static ref STATUS: Mutex<SteamStatusInfo> = Mutex::new(SteamStatusInfo::default());
    static ref ROOM: Mutex<SteamRoomInfo> = Mutex::new(SteamRoomInfo::default());
    static ref INBOUND: Mutex<Option<StreamSink<AppInboundEventC>>> = Mutex::new(None);
    static ref STATUS_SINK: Mutex<Option<StreamSink<SteamStatusInfo>>> = Mutex::new(None);
    static ref BOOT_FAILED_AT: Mutex<Option<Instant>> = Mutex::new(None);
    /// 复现专用日志开关：`ASTRAL_STEAM_DEBUG=1|true|yes` 时落盘。
    static ref STEAM_DEBUG: bool = std::env::var("ASTRAL_STEAM_DEBUG")
        .map(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes"))
        .unwrap_or(false);
    /// 待处理的好友邀请大厅 id：来自 `GameLobbyJoinRequested` 或启动参数
    /// `+connect_lobby <id>`，由 Dart 轮询后清空。
    static ref PENDING_INVITE: Mutex<Option<u64>> = Mutex::new(None);
    /// 本次房间内是否真正调用过 `activate_invite_dialog`，双机自检报告用。
    static ref INVITE_DIALOG_CALLED: AtomicBool = AtomicBool::new(false);
}

/// Steam 大厅回调结果：Steam 回调只在 `run_callbacks()` 里派发，闭包把结果
/// 塞进通道，引擎在同一 tick 的 `poll_lobby_events()` 里回收。
enum LobbyEvent {
    Created(Result<u64, String>),
    Joined(Result<u64, String>),
    Listed(Result<Vec<u64>, String>),
}

enum LobbyOp {
    Create {
        game_id: String,
        gate: String,
        name: String,
        join_token: String,
        nickname: String,
    },
    Join {
        game_id: String,
        join_token: String,
        nickname: String,
    },
    Peek {
        game_id: String,
    },
    Search {
        game_id: String,
    },
}

enum LobbyReply {
    One(oneshot::Sender<Result<SteamLobbyInfo, String>>),
    Many(oneshot::Sender<Result<Vec<SteamLobbyInfo>, String>>),
}

struct PendingLobby {
    op: LobbyOp,
    reply: LobbyReply,
    deadline: Instant,
}

/// 客人「大厅已加入、隧道还没拿到 Welcome」的过渡态。
///
/// 大厅 API 要等隧道真正可用才返回，所以把 start_room 的回执接过来，
/// 每个 tick 检查一次（`start_room` 的回执来自 WELCOME 或超时）。
struct LobbyForward {
    rx: oneshot::Receiver<Result<SteamRoomInfo, String>>,
    reply: Option<oneshot::Sender<Result<SteamLobbyInfo, String>>>,
    info: SteamLobbyInfo,
}

/// 复现期日志：仅调试开关打开时写入临时目录，默认路径
/// `%TEMP%\astral-steam-debug.log`。用于双账号现场取证，不影响正常行为。
fn debug_log(event: &str, detail: impl AsRef<str>) {
    if !*STEAM_DEBUG {
        return;
    }
    use std::io::Write;
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let path = std::env::temp_dir().join("astral-steam-debug.log");
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(f, "{ts} {event} {}", detail.as_ref());
    }
}

fn emit_status() {
    let snapshot = match STATUS.lock() {
        Ok(s) => s.clone(),
        Err(_) => return,
    };
    let Ok(guard) = STATUS_SINK.lock() else {
        return;
    };
    if let Some(sink) = guard.as_ref() {
        // Dart 侧取消订阅后 add 会失败；下次订阅会覆盖 sink。
        let _ = sink.add(snapshot);
    }
}

fn set_status(status: SteamStatusInfo) {
    if let Ok(mut s) = STATUS.lock() {
        *s = status;
    }
    emit_status();
}

fn update_status(f: impl FnOnce(&mut SteamStatusInfo)) {
    if let Ok(mut s) = STATUS.lock() {
        f(&mut s);
    } else {
        return;
    }
    emit_status();
}

fn publish_room(room: SteamRoomInfo) {
    if let Ok(mut r) = ROOM.lock() {
        *r = room;
    }
}

fn emit_inbound(event: AppInboundEventC) {
    let Ok(guard) = INBOUND.lock() else {
        return;
    };
    let Some(sink) = guard.as_ref() else {
        return;
    };
    if sink.add(event).is_err() {
        // Dart 侧已取消订阅；下次重新订阅会覆盖。
    }
}

/// 读取当前 Steam 状态；首次调用会拉起后台线程。
pub(crate) fn status() -> SteamStatusInfo {
    let _ = ensure_boot();
    STATUS.lock().map(|s| s.clone()).unwrap_or_default()
}

pub(crate) fn room_info() -> SteamRoomInfo {
    ROOM.lock().map(|r| r.clone()).unwrap_or_default()
}

pub(crate) fn subscribe_app_inbound(sink: StreamSink<AppInboundEventC>) {
    // 替换时旧 sink 会在此处 drop：FRB 的 StreamSink 在最后一个克隆被释放时
    // 才向 Dart 发送关闭消息，Dart 侧旧订阅的 `async*` 生成器收到关闭后才会退出，
    // 否则它的 `cancel()` Future 永远不会完成（退出房间会卡死）。
    let _old = INBOUND
        .lock()
        .ok()
        .and_then(|mut guard| guard.replace(sink));
}

/// 关闭入站订阅：房间结束时不再向 Dart 推送事件，并让旧订阅正常收尾。
pub(crate) fn close_app_inbound() {
    // 取出并 drop 最后一个 sink 克隆，FRB 会据此关闭 Dart 侧流。
    let _old = INBOUND.lock().ok().and_then(|mut guard| guard.take());
}

/// 订阅 Steam 状态变化（登录 / 断线 / SDR 就绪 / 房间）；订阅时立即推送快照。
pub(crate) fn subscribe_status(sink: StreamSink<SteamStatusInfo>) {
    let _ = ensure_boot();
    let _old = STATUS_SINK
        .lock()
        .ok()
        .and_then(|mut guard| guard.replace(sink));
    emit_status();
}

/// SDR 中继回调：状态一变就写入快照并推给 Dart（`poll_relay` 仅作兜底）。
fn apply_relay_ready(ready: bool) {
    let unchanged = STATUS
        .lock()
        .map(|s| s.relay_ready == ready)
        .unwrap_or(true);
    if unchanged {
        return;
    }
    update_status(|s| {
        s.relay_ready = ready;
        if ready {
            // 只覆盖中继相关的提示，别把房间 / 成员消息冲掉。
            if s.message.starts_with("已连接 Steam")
                || s.message.starts_with("SDR 中继")
                || s.message.starts_with("正在获取中继")
            {
                s.message = "SDR 中继网络已就绪".to_string();
            }
        } else {
            s.message = "SDR 中继网络已断开，正在重连…".to_string();
        }
    });
}

pub(crate) fn my_peer_id() -> u32 {
    ROOM.lock().map(|r| r.self_peer_id).unwrap_or(0)
}

fn resolve_appid() -> AppId {
    if let Ok(v) = std::env::var("ASTRAL_STEAM_APPID") {
        if let Ok(id) = v.trim().parse::<u32>() {
            return AppId(id);
        }
    }
    for path in ["steam_appid.txt", "data/steam_appid.txt"] {
        if let Ok(text) = std::fs::read_to_string(path) {
            let first = text.lines().next().unwrap_or("").trim();
            if let Ok(id) = first.parse::<u32>() {
                return AppId(id);
            }
        }
    }
    AppId(480)
}

fn ensure_boot() -> Option<Sender<Cmd>> {
    let mut guard = TX.lock().ok()?;
    if let Some(tx) = guard.as_ref() {
        return Some(tx.clone());
    }
    if let Ok(failed) = BOOT_FAILED_AT.lock() {
        if failed.map(|at| at.elapsed() < BOOT_RETRY).unwrap_or(false) {
            return None;
        }
    }
    let (tx, rx) = mpsc::channel::<Cmd>();
    thread::Builder::new()
        .name("astral-steam".to_string())
        .spawn(move || engine_thread(rx))
        .ok()?;
    *guard = Some(tx.clone());
    Some(tx)
}

fn boot_error() -> String {
    STATUS
        .lock()
        .map(|s| s.message.clone())
        .unwrap_or_else(|_| "Steam 线程未启动".to_string())
}

fn tx_handle() -> Result<Sender<Cmd>, String> {
    ensure_boot().ok_or_else(boot_error)
}

pub(crate) async fn start(
    host: bool,
    host_steam_id: String,
    join_token: String,
    nickname: String,
    game_id: String,
) -> Result<SteamStatusInfo, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::Start {
        host,
        host_steam_id,
        join_token,
        nickname,
        game_id,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    match tokio::time::timeout(START_TIMEOUT, reply_rx).await {
        Ok(Ok(Ok(_))) => Ok(status()),
        Ok(Ok(Err(e))) => Err(e),
        Ok(Err(_)) => Err("Steam 线程已退出".to_string()),
        Err(_) => {
            let _ = tx.send(Cmd::Stop);
            Err("Steam 组网启动超时（15 秒内未能建立连接）".to_string())
        }
    }
}

pub(crate) fn stop() -> Result<(), String> {
    if let Ok(guard) = TX.lock() {
        if let Some(tx) = guard.as_ref() {
            let _ = tx.send(Cmd::Stop);
        }
    }
    Ok(())
}

/// 等待大厅操作的异步回执。
async fn await_lobby<T>(
    rx: oneshot::Receiver<Result<T, String>>,
    timeout: Duration,
) -> Result<T, String> {
    match tokio::time::timeout(timeout, rx).await {
        Ok(Ok(v)) => v,
        Ok(Err(_)) => Err("Steam 线程已退出".to_string()),
        Err(_) => Err("Steam 大厅操作超时，请重试".to_string()),
    }
}

/// 创建公开大厅并直接开房（写 `ag_*` 标签 + 开 P2P 监听）。
#[allow(clippy::too_many_arguments)]
pub(crate) async fn create_lobby(
    game_id: String,
    name: String,
    gate: String,
    max_members: u32,
    join_token: String,
    nickname: String,
) -> Result<SteamLobbyInfo, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::LobbyCreate {
        game_id,
        name,
        gate,
        max_members,
        join_token,
        nickname,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, LOBBY_TIMEOUT + START_TIMEOUT).await
}

/// 搜索本游戏的大厅（服务端 `ag_game` 过滤 + 本地二次校验）。
pub(crate) async fn search(game_id: String) -> Result<Vec<SteamLobbyInfo>, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::LobbySearch {
        game_id,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, LOBBY_TIMEOUT).await
}

/// 加入大厅并连上房主；成功时隧道已可用。
pub(crate) async fn join_lobby(
    lobby_id: u64,
    game_id: String,
    join_token: String,
    nickname: String,
) -> Result<SteamLobbyInfo, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::LobbyJoin {
        lobby_id,
        game_id,
        join_token,
        nickname,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, LOBBY_TIMEOUT + START_TIMEOUT).await
}

/// 诊断用：验证「离线超过宽限期的成员会被真正摘除」。
pub(crate) async fn debug_ghost_probe() -> Result<String, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::DebugGhost { reply: reply_tx })
        .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, Duration::from_secs(5)).await
}

/// 只读大厅元数据（加入后立刻离开），用于邀请进房前确认门槛。
pub(crate) async fn peek_lobby(lobby_id: u64) -> Result<SteamLobbyInfo, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::LobbyPeek {
        lobby_id,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, LOBBY_TIMEOUT).await
}

/// 离开当前大厅（同时停止隧道）。
pub(crate) async fn leave_lobby() -> Result<(), String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::LobbyLeave { reply: reply_tx })
        .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, Duration::from_secs(5)).await
}

/// 设置大厅是否可被搜索到。
pub(crate) async fn set_lobby_joinable(joinable: bool) -> Result<(), String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::LobbySetJoinable {
        joinable,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, Duration::from_secs(5)).await
}

/// 打开 Steam 原生好友邀请界面。
///
/// 覆盖层未开启时 `activate_invite_dialog` 没有任何可见效果，因此引擎会先
/// 检查 `IsOverlayEnabled`，不可用直接返回可展示给用户的失败原因。
pub(crate) async fn invite_dialog() -> Result<String, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::LobbyInviteDialog { reply: reply_tx })
        .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, Duration::from_secs(5)).await
}

/// 直接邀请指定好友进入当前大厅（不依赖覆盖层）。
pub(crate) async fn invite_friend(friend_steam_id: u64) -> Result<String, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::LobbyInviteFriend {
        friend_steam_id,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, Duration::from_secs(5)).await
}

/// 组网诊断快照。
pub(crate) async fn lobby_diag() -> Result<SteamLobbyDiag, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::LobbyDiag { reply: reply_tx })
        .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, Duration::from_secs(5)).await
}

/// 诊断用：客人侧宽限过滤（注入房主离线超宽限期，跑真实 prune）。
pub(crate) async fn debug_guest_roster_probe() -> Result<String, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::DebugGuestRoster { reply: reply_tx })
        .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    await_lobby(reply_rx, Duration::from_secs(5)).await
}

/// 读取待处理的好友邀请大厅 id（Dart 轮询；读完需要显式清空）。
pub(crate) fn peer_pending_lobby_invite() -> Option<String> {
    let _ = ensure_boot();
    PENDING_INVITE
        .lock()
        .ok()
        .and_then(|g| *g)
        .map(|id| id.to_string())
}

pub(crate) fn clear_pending_lobby_invite() {
    if let Ok(mut g) = PENDING_INVITE.lock() {
        *g = None;
    }
}

pub(crate) async fn app_call(
    dst_peer_id: u32,
    channel: String,
    request_id: u64,
    payload: Vec<u8>,
    flags: u32,
    timeout_ms: i32,
) -> Result<AppCallResultC, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::AppCall {
        dst_peer_id,
        channel,
        request_id,
        payload,
        flags,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    let wait = Duration::from_millis(if timeout_ms <= 0 {
        5000
    } else {
        timeout_ms as u64
    });
    match tokio::time::timeout(wait, reply_rx).await {
        Ok(Ok(Ok(v))) => Ok(v),
        Ok(Ok(Err(e))) => Err(e),
        Ok(Err(_)) => Err("Steam RPC 已取消".to_string()),
        Err(_) => Err("Request timeout".to_string()),
    }
}

pub(crate) async fn app_notify(
    dst_peer_id: u32,
    channel: String,
    payload: Vec<u8>,
) -> Result<(), String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::AppNotify {
        dst_peer_id,
        channel,
        payload,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    match tokio::time::timeout(Duration::from_secs(3), reply_rx).await {
        Ok(Ok(v)) => v,
        Ok(Err(_)) => Err("Steam RPC 已取消".to_string()),
        Err(_) => Err("Request timeout".to_string()),
    }
}

pub(crate) async fn app_reply(
    token: u64,
    status: i32,
    error_msg: String,
    payload: Vec<u8>,
) -> Result<bool, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::AppReply {
        token,
        status,
        error_msg,
        payload,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    match tokio::time::timeout(Duration::from_secs(3), reply_rx).await {
        Ok(Ok(v)) => Ok(v),
        Ok(Err(_)) => Err("Steam 线程已退出".to_string()),
        Err(_) => Ok(false),
    }
}

pub(crate) async fn peer_ping(dst_peer_id: u32, timeout_ms: i32) -> Result<i64, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::PeerPing {
        dst_peer_id,
        reply: reply_tx,
    })
    .map_err(|e| format!("Steam 线程不可用: {e}"))?;
    let wait = Duration::from_millis(if timeout_ms <= 0 {
        5000
    } else {
        timeout_ms as u64
    });
    match tokio::time::timeout(wait, reply_rx).await {
        Ok(Ok(Ok(ms))) => Ok(ms as i64),
        Ok(Ok(Err(e))) => Err(e),
        Ok(Err(_)) => Err("Steam RPC 已取消".to_string()),
        Err(_) => Err("Request timeout".to_string()),
    }
}

// ---------------------------------------------------------------------------
// 引擎
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq, Eq)]
enum Role {
    Idle,
    Host,
    Guest,
}

struct Member {
    peer_id: u32,
    steam_id: u64,
    nickname: String,
    vip: Ipv4Addr,
    online: bool,
    is_host: bool,
    latency_ms: u32,
    /// 本机到该成员的 Steam 连接是否经中继转发（false = 直连）。
    via_relay: bool,
    bytes_in: u64,
    bytes_out: u64,
    last_seen: Instant,
    /// 首次观察到该成员离线的时刻；在线时为 `None`。
    offline_since: Option<Instant>,
}

struct PendingEntry {
    kind: PendingKind,
    at: Instant,
}

enum PendingKind {
    Call(oneshot::Sender<Result<AppCallResultC, String>>),
    Ping(oneshot::Sender<Result<u64, String>>),
}

struct Engine {
    client: Client,
    sockets: NetworkingSockets,
    self_steam_id: u64,
    persona: String,
    role: Role,
    join_token: String,
    nickname: String,
    /// 本房间的游戏标识（`ag_game`）；HELLO 里带出去由房主二次校验。
    game_id: String,

    /// 当前所在的 Steam 大厅；关房时必须先 `set_lobby_joinable(false)` 再离开。
    lobby_id: Option<u64>,
    /// 自己最后一次设置的可加入状态（Steam 没有读取接口，诊断用）。
    lobby_joinable: bool,
    lobby_cache: lobby::LobbyCache,
    lobby_tx: mpsc::Sender<LobbyEvent>,
    lobby_rx: mpsc::Receiver<LobbyEvent>,
    pending_lobby: Option<PendingLobby>,
    lobby_forward: Option<LobbyForward>,

    tun: Option<TunRoom>,
    my_vip: Ipv4Addr,
    my_peer_id: u32,

    // 房主
    listen: Option<ListenSocket>,
    conns: HashMap<u64, NetConnection>,
    members: HashMap<u64, Member>,
    assign_cache: HashMap<u64, (u32, Ipv4Addr, Instant)>,

    // 客人
    host_steam_id: u64,
    host_conn: Option<NetConnection>,
    /// 客人到房主的 Steam 连接是否经中继转发。
    host_via_relay: bool,
    hello_sent: bool,
    reconnect_at: Option<Instant>,
    start_reply: Option<oneshot::Sender<Result<SteamRoomInfo, String>>>,
    start_deadline: Option<Instant>,

    roster: Vec<RosterEntry>,
    /// 客人侧观察到的成员离线时刻：Roster 里只有 online 位，没有时间戳，
    /// 这里本地计时，超宽限期仍未回来就不再显示。
    guest_offline_since: HashMap<u64, Instant>,

    /// 客机发出通往房主 PING 的时刻。
    guest_ping_at: Option<Instant>,
    /// 客机实测的本机↔房主 RTT；房主下发的 Roster 里该字段恒为 0，
    /// 收到 Roster 后要用这个值回填房主条目，避免延迟显示被刷回 0ms。
    guest_host_latency_ms: u32,

    batch_up: HashMap<Ipv4Addr, Vec<u8>>,
    batch_flood: Vec<u8>,

    pending: HashMap<u64, PendingEntry>,
    inbound_replies: HashMap<u64, (Ipv4Addr, u64)>,
    next_token: u64,
    next_request: u64,

    flood_seen: HashMap<u64, Instant>,

    relay_ready: bool,
    last_ready_check: Instant,
    last_heartbeat: Instant,
    last_roster_at: Instant,
    last_publish: Instant,
    last_ping_probe: Instant,
    last_relay_check: Instant,

    rx_bytes: u64,
    tx_bytes: u64,
    drops: u64,
    message: String,
    /// 登录 / 断线回调句柄；Drop 时自动注销。
    _callbacks: Vec<CallbackHandle>,
}

impl Engine {
    fn new(client: Client, self_steam_id: u64, persona: String) -> Self {
        let sockets = client.networking_sockets();
        // 登录状态事件：Steam 掉线/重连后不用等轮询。
        let callbacks = vec![
            client.register_callback(|_: SteamServersConnected| {
                update_status(|s| s.logged_on = true);
            }),
            client.register_callback(|_: SteamServersDisconnected| {
                update_status(|s| s.logged_on = false);
            }),
            // 好友在 Steam 里点「加入游戏」：直接把大厅 id 挂起，Dart 轮询后进房。
            client.register_callback(|ev: GameLobbyJoinRequested| {
                let lobby_id = ev.lobby_steam_id.raw();
                debug_log(
                    "invite_lobby_join",
                    format!("lobby={lobby_id} friend={}", ev.friend_steam_id.raw()),
                );
                if lobby_id != 0 {
                    if let Ok(mut pending) = PENDING_INVITE.lock() {
                        *pending = Some(lobby_id);
                    }
                }
            }),
            // `invite_user_to_game` 走的是 connect string，不是 lobby 回调。
            client.register_callback(|ev: GameRichPresenceJoinRequested| {
                debug_log("invite_connect_string", format!("connect={}", ev.connect));
                if let Some(lobby_id) = lobby::parse_connect_lobby(&ev.connect) {
                    if let Ok(mut pending) = PENDING_INVITE.lock() {
                        *pending = Some(lobby_id);
                    }
                }
            }),
        ];
        // SDR 中继就绪状态：状态变化时立即回调，避免 waitReady 等 2s 轮询。
        client
            .networking_utils()
            .relay_network_status_callback(|status| {
                apply_relay_ready(status.availability() == Ok(NetworkingAvailability::Current));
            });
        let (lobby_tx, lobby_rx) = mpsc::channel();
        Self {
            client,
            sockets,
            self_steam_id,
            persona,
            role: Role::Idle,
            join_token: String::new(),
            nickname: String::new(),
            game_id: String::new(),
            lobby_id: None,
            lobby_joinable: false,
            lobby_cache: lobby::LobbyCache::default(),
            lobby_tx,
            lobby_rx,
            pending_lobby: None,
            lobby_forward: None,
            tun: None,
            my_vip: Ipv4Addr::UNSPECIFIED,
            my_peer_id: 0,
            listen: None,
            conns: HashMap::new(),
            members: HashMap::new(),
            assign_cache: HashMap::new(),
            host_steam_id: 0,
            host_conn: None,
            host_via_relay: false,
            hello_sent: false,
            reconnect_at: None,
            start_reply: None,
            start_deadline: None,
            roster: Vec::new(),
            guest_offline_since: HashMap::new(),
            guest_ping_at: None,
            guest_host_latency_ms: 0,
            batch_up: HashMap::new(),
            batch_flood: Vec::new(),
            pending: HashMap::new(),
            inbound_replies: HashMap::new(),
            next_token: 0,
            next_request: 0,
            flood_seen: HashMap::new(),
            relay_ready: false,
            last_ready_check: Instant::now(),
            last_heartbeat: Instant::now(),
            last_roster_at: Instant::now() - Duration::from_secs(10),
            last_publish: Instant::now() - Duration::from_secs(10),
            last_ping_probe: Instant::now() - Duration::from_secs(10),
            last_relay_check: Instant::now() - Duration::from_secs(10),
            rx_bytes: 0,
            tx_bytes: 0,
            drops: 0,
            message: String::new(),
            _callbacks: callbacks,
        }
    }

    fn tick_interval(&self) -> Duration {
        if self.role == Role::Idle {
            Duration::from_millis(40)
        } else {
            Duration::from_millis(8)
        }
    }

    fn handle_cmd(&mut self, cmd: Cmd) {
        match cmd {
            Cmd::Start {
                host,
                host_steam_id,
                join_token,
                nickname,
                game_id,
                reply,
            } => {
                // 与大厅里写入的 `ag_game` 保持同一套 slug，否则 HELLO 校验会误判。
                self.game_id = lobby::normalize_game_id(&game_id).unwrap_or_default();
                self.start_room(host, host_steam_id, join_token, nickname, reply)
            }
            Cmd::LobbyCreate {
                game_id,
                name,
                gate,
                max_members,
                join_token,
                nickname,
                reply,
            } => self.lobby_create(game_id, name, gate, max_members, join_token, nickname, reply),
            Cmd::LobbySearch { game_id, reply } => self.lobby_search(game_id, reply),
            Cmd::LobbyJoin {
                lobby_id,
                game_id,
                join_token,
                nickname,
                reply,
            } => self.lobby_join(lobby_id, game_id, join_token, nickname, reply),
            Cmd::LobbyPeek { lobby_id, reply } => self.lobby_peek(lobby_id, reply),
            Cmd::DebugGhost { reply } => {
                let _ = reply.send(self.debug_ghost_probe());
            }
            Cmd::LobbyLeave { reply } => {
                self.shutdown_room("已退出 Steam 大厅");
                let _ = reply.send(Ok(()));
            }
            Cmd::LobbySetJoinable { joinable, reply } => {
                let Some(lobby_id) = self.lobby_id else {
                    let _ = reply.send(Err("当前没有 Steam 大厅".to_string()));
                    return;
                };
                let ok = self
                    .client
                    .matchmaking()
                    .set_lobby_joinable(LobbyId::from_raw(lobby_id), joinable);
                if ok {
                    self.lobby_joinable = joinable;
                }
                debug_log(
                    "lobby_set_joinable",
                    format!("lobby={lobby_id} joinable={joinable} ok={ok}"),
                );
                let _ = reply.send(if ok {
                    Ok(())
                } else {
                    Err("设置大厅可加入状态失败".to_string())
                });
            }
            Cmd::LobbyInviteDialog { reply } => {
                let Some(lobby_id) = self.lobby_id else {
                    let _ = reply.send(Err("当前没有 Steam 大厅".to_string()));
                    return;
                };
                let overlay = self.client.utils().is_overlay_enabled();
                debug_log(
                    "lobby_invite_dialog",
                    format!("lobby={lobby_id} overlay={overlay} called={overlay}"),
                );
                if !overlay {
                    // 覆盖层不可用时 activate_invite_dialog 不会有任何可见效果，
                    // 与其静默调用，不如明确告诉用户原因和替代路径。
                    let _ = reply.send(Err(
                        "需要开启 Steam 覆盖层才能邀请好友（Steam → 设置 → 游戏中 → 启用 Steam 覆盖层）。\
                         也可以让好友用「加入 → 搜索房间」进入。"
                            .to_string(),
                    ));
                    return;
                }
                self.client
                    .friends()
                    .activate_invite_dialog(LobbyId::from_raw(lobby_id));
                INVITE_DIALOG_CALLED.store(true, Ordering::Relaxed);
                let _ = reply.send(Ok(
                    "已请求唤起 Steam 邀请面板（只打开面板，不代表已发送邀请）".to_string()
                ));
            }
            Cmd::LobbyInviteFriend {
                friend_steam_id,
                reply,
            } => {
                let Some(lobby_id) = self.lobby_id else {
                    let _ = reply.send(Err("当前没有 Steam 大厅".to_string()));
                    return;
                };
                let accepted = self.client.matchmaking().invite_user_to_lobby(
                    LobbyId::from_raw(lobby_id),
                    SteamId::from_raw(friend_steam_id),
                );
                debug_log(
                    "lobby_invite_friend",
                    format!("lobby={lobby_id} friend={friend_steam_id} accepted={accepted}"),
                );
                let _ = reply.send(if accepted {
                    Ok("Steam 已受理大厅邀请；对方是否可见取决于在线状态与好友关系".to_string())
                } else {
                    Err("Steam 未受理该邀请：请确认对方在好友列表中，或改用邀请面板 / 搜索房间"
                        .to_string())
                });
            }
            Cmd::LobbyDiag { reply } => {
                let _ = reply.send(self.lobby_diag());
            }
            Cmd::DebugGuestRoster { reply } => {
                let _ = reply.send(self.debug_guest_roster_probe());
            }
            Cmd::Stop => self.shutdown_room("Steam 组网已停止"),
            Cmd::AppCall {
                dst_peer_id,
                channel,
                request_id,
                payload,
                flags,
                reply,
            } => self.do_app_call(dst_peer_id, channel, request_id, payload, flags, reply),
            Cmd::AppNotify {
                dst_peer_id,
                channel,
                payload,
                reply,
            } => {
                let Some(vip) = self.vip_for_peer(dst_peer_id) else {
                    let _ = reply.send(Err(format!("成员 {dst_peer_id} 不在房间内")));
                    return;
                };
                let body = proto::rpc_call(
                    proto::RPC_NOTIFY,
                    &proto::RpcCall {
                        request_id: 0,
                        flags: 0,
                        channel,
                        payload,
                    },
                );
                let ok = self.send_rpc_frame(vip, &body);
                let _ = reply.send(if ok {
                    Ok(())
                } else {
                    Err("发送失败：房间连接不可用".to_string())
                });
            }
            Cmd::AppReply {
                token,
                status,
                error_msg,
                payload,
                reply,
            } => {
                let Some((caller_vip, request_id)) = self.inbound_replies.remove(&token) else {
                    let _ = reply.send(false);
                    return;
                };
                let body = proto::rpc_reply(&proto::RpcReply {
                    request_id,
                    status,
                    error_msg,
                    payload,
                });
                let ok = self.send_rpc_frame(caller_vip, &body);
                let _ = reply.send(ok);
            }
            Cmd::PeerPing { dst_peer_id, reply } => {
                let Some(vip) = self.vip_for_peer(dst_peer_id) else {
                    let _ = reply.send(Err(format!("成员 {dst_peer_id} 不在房间内")));
                    return;
                };
                // 自己的连接延迟直接取 Steam 实时状态，不必绕一圈 RPC。
                if dst_peer_id == self.my_peer_id {
                    let _ = reply.send(Ok(0));
                    return;
                }
                self.next_request += 1;
                let rid = self.next_request;
                self.pending.insert(
                    rid,
                    PendingEntry {
                        kind: PendingKind::Ping(reply),
                        at: Instant::now(),
                    },
                );
                let body = proto::rpc_ping(rid);
                if !self.send_rpc_frame(vip, &body) {
                    if let Some(PendingEntry {
                        kind: PendingKind::Ping(tx),
                        ..
                    }) = self.pending.remove(&rid)
                    {
                        let _ = tx.send(Err("发送失败：房间连接不可用".to_string()));
                    }
                }
            }
        }
    }

    /// 创建公开大厅：先重置旧房间，再异步建大厅，成功后开隧道并写 `ag_*` 标签。
    #[allow(clippy::too_many_arguments)]
    fn lobby_create(
        &mut self,
        game_id: String,
        name: String,
        gate: String,
        max_members: u32,
        join_token: String,
        nickname: String,
        reply: oneshot::Sender<Result<SteamLobbyInfo, String>>,
    ) {
        self.shutdown_room("切换 Steam 大厅");
        let Some(game_id) = lobby::normalize_game_id(&game_id) else {
            let _ = reply.send(Err("游戏标识为空，无法创建可被搜索的房间".to_string()));
            return;
        };
        let gate = Gate::parse(&gate).unwrap_or(Gate::Basic);
        let cap = if max_members == 0 {
            DEFAULT_LOBBY_CAP
        } else {
            max_members.clamp(2, 250)
        };
        let room_name = if name.trim().is_empty() {
            format!("{game_id} 的房间")
        } else {
            name.trim().to_string()
        };
        let tx = self.lobby_tx.clone();
        self.client
            .matchmaking()
            .create_lobby(LobbyType::Public, cap, move |res| {
                let mapped = res
                    .map(|l| l.raw())
                    .map_err(|e| format!("创建 Steam 大厅失败: {e:?}"));
                let _ = tx.send(LobbyEvent::Created(mapped));
            });
        debug_log(
            "lobby_create_start",
            format!("game={game_id} gate={} cap={cap}", gate.as_str()),
        );
        self.pending_lobby = Some(PendingLobby {
            op: LobbyOp::Create {
                game_id,
                gate: gate.as_str().to_string(),
                name: room_name,
                join_token,
                nickname,
            },
            reply: LobbyReply::One(reply),
            deadline: Instant::now() + LOBBY_TIMEOUT,
        });
        self.message = "正在创建 Steam 大厅…".to_string();
    }

    /// 搜索本游戏的大厅：服务端 `ag_game` 过滤，结果回来后再本地校验。
    fn lobby_search(
        &mut self,
        game_id: String,
        reply: oneshot::Sender<Result<Vec<SteamLobbyInfo>, String>>,
    ) {
        let Some(game_id) = lobby::normalize_game_id(&game_id) else {
            let _ = reply.send(Err("缺少游戏标识，无法搜索房间".to_string()));
            return;
        };
        let mm = self.client.matchmaking();
        // 测试开关：Steam 端 `ag_game` 过滤正常时，本地二次校验永远筛不掉东西，
        // 等于没被执行过。置位后不加服务端过滤，让所有大厅都进本地校验。
        let force_local = std::env::var("ASTRAL_STEAM_FORCE_LOCAL_VALIDATE")
            .map(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes"))
            .unwrap_or(false);
        if force_local {
            mm.set_lobby_list_filter(LobbyListFilter::default());
        } else {
            mm.set_lobby_list_filter(LobbyListFilter {
                string: Some(vec![StringFilter(
                    LobbyKey::new(lobby::KEY_GAME),
                    game_id.as_str(),
                    StringFilterKind::Equal,
                )]),
                ..Default::default()
            });
        }
        let tx = self.lobby_tx.clone();
        mm.request_lobby_list(move |res| {
            let mapped = res
                .map(|list| list.into_iter().map(|l| l.raw()).collect::<Vec<_>>())
                .map_err(|e| format!("搜索 Steam 大厅失败: {e:?}"));
            let _ = tx.send(LobbyEvent::Listed(mapped));
        });
        debug_log(
            "lobby_search_start",
            format!("game={game_id} force_local={force_local}"),
        );
        self.pending_lobby = Some(PendingLobby {
            op: LobbyOp::Search { game_id },
            reply: LobbyReply::Many(reply),
            deadline: Instant::now() + LOBBY_TIMEOUT,
        });
    }

    /// 加入大厅：先校验 `ag_*`，再连房主；隧道可用后才回执。
    fn lobby_join(
        &mut self,
        lobby_id: u64,
        game_id: String,
        join_token: String,
        nickname: String,
        reply: oneshot::Sender<Result<SteamLobbyInfo, String>>,
    ) {
        if lobby_id == 0 {
            let _ = reply.send(Err("无效的大厅 ID".to_string()));
            return;
        }
        // 邀请进房时不知道游戏标识（邀请里只有大厅 id），允许为空：
        // 此时只校验协议版本，游戏由大厅元数据自己说明。
        let game_id = if game_id.trim().is_empty() {
            String::new()
        } else {
            let Some(g) = lobby::normalize_game_id(&game_id) else {
                let _ = reply.send(Err("缺少游戏标识，无法加入房间".to_string()));
                return;
            };
            g
        };
        self.shutdown_room("切换 Steam 大厅");
        let tx = self.lobby_tx.clone();
        self.client
            .matchmaking()
            .join_lobby(LobbyId::from_raw(lobby_id), move |res| {
                let mapped = res.map(|l| l.raw()).map_err(|_| {
                    "加入 Steam 大厅失败（房间已关闭、已满员或 Steam 暂时不可用）".to_string()
                });
                let _ = tx.send(LobbyEvent::Joined(mapped));
            });
        debug_log("lobby_join_start", format!("lobby={lobby_id} game={game_id}"));
        self.pending_lobby = Some(PendingLobby {
            op: LobbyOp::Join {
                game_id,
                join_token,
                nickname,
            },
            reply: LobbyReply::One(reply),
            deadline: Instant::now() + LOBBY_TIMEOUT,
        });
    }

    /// 加入大厅只为读元数据（门槛 / 游戏 / 人数），读完立刻离开。
    fn lobby_peek(
        &mut self,
        lobby_id: u64,
        reply: oneshot::Sender<Result<SteamLobbyInfo, String>>,
    ) {
        if lobby_id == 0 {
            let _ = reply.send(Err("无效的大厅 ID".to_string()));
            return;
        }
        let tx = self.lobby_tx.clone();
        self.client
            .matchmaking()
            .join_lobby(LobbyId::from_raw(lobby_id), move |res| {
                let mapped = res.map(|l| l.raw()).map_err(|_| {
                    "大厅已关闭或已满员（Steam 无法加入）".to_string()
                });
                let _ = tx.send(LobbyEvent::Joined(mapped));
            });
        debug_log("lobby_peek_start", format!("lobby={lobby_id}"));
        self.pending_lobby = Some(PendingLobby {
            op: LobbyOp::Peek {
                game_id: String::new(),
            },
            reply: LobbyReply::One(reply),
            deadline: Instant::now() + LOBBY_TIMEOUT,
        });
    }

    fn poll_lobby_events(&mut self) {
        loop {
            let Ok(ev) = self.lobby_rx.try_recv() else {
                break;
            };
            match ev {
                LobbyEvent::Created(res) => self.on_lobby_created(res),
                LobbyEvent::Joined(res) => self.on_lobby_joined(res),
                LobbyEvent::Listed(res) => self.on_lobby_listed(res),
            }
        }
    }

    fn on_lobby_created(&mut self, res: Result<u64, String>) {
        let Some(PendingLobby {
            op:
                LobbyOp::Create {
                    game_id,
                    gate,
                    name,
                    join_token,
                    nickname,
                },
            reply: LobbyReply::One(reply),
            ..
        }) = self.pending_lobby.take()
        else {
            return;
        };
        let lobby_id = match res {
            Ok(id) => id,
            Err(e) => {
                debug_log("lobby_create_fail", format!("err={e}"));
                self.message = e.clone();
                let _ = reply.send(Err(e));
                return;
            }
        };
        // 先开隧道，再写标签：start_room 会重置上一个房间（含旧大厅），
        // 此时 self.lobby_id 还没指向新大厅，不会被误伤。
        let (tx, mut rx) = oneshot::channel();
        self.start_room(true, String::new(), join_token, nickname, tx);
        match rx.try_recv() {
            Ok(Ok(room)) => {
                self.lobby_id = Some(lobby_id);
                self.game_id = game_id.clone();
                let lid = LobbyId::from_raw(lobby_id);
                let mm = self.client.matchmaking();
                let host_id = self.self_steam_id.to_string();
                let players = room.member_count.max(1).to_string();
                mm.set_lobby_data(lid, lobby::KEY_GAME, &game_id);
                mm.set_lobby_data(lid, lobby::KEY_VER, lobby::PROTOCOL_VERSION);
                mm.set_lobby_data(lid, lobby::KEY_GATE, &gate);
                mm.set_lobby_data(lid, lobby::KEY_NAME, &name);
                mm.set_lobby_data(lid, lobby::KEY_HOST, &host_id);
                mm.set_lobby_data(lid, lobby::KEY_PLAYERS, &players);
                let joinable = mm.set_lobby_joinable(lid, true);
                self.lobby_joinable = joinable;
                let readback = mm.lobby_data(lid, lobby::KEY_GAME).unwrap_or_default();
                let ver_readback = mm.lobby_data(lid, lobby::KEY_VER).unwrap_or_default();
                let gate_readback = mm.lobby_data(lid, lobby::KEY_GATE).unwrap_or_default();
                let name_readback = mm.lobby_data(lid, lobby::KEY_NAME).unwrap_or_default();
                let capacity = mm.lobby_member_limit(lid).unwrap_or(0) as u32;
                let members = mm.lobby_member_count(lid) as u32;
                debug_log(
                    "lobby_create_ok",
                    format!(
                        "lobby={lobby_id} game={readback} ver={ver_readback} gate={gate_readback} \
                         name={name_readback} joinable={joinable} members={members} cap={capacity}"
                    ),
                );
                self.message = format!("Steam 大厅已开启（游戏 {game_id}）");
                let _ = reply.send(Ok(SteamLobbyInfo {
                    lobby_id: lobby_id.to_string(),
                    game_id,
                    name,
                    gate,
                    version: lobby::PROTOCOL_VERSION.to_string(),
                    host_steam_id: host_id,
                    players: room.member_count.max(1),
                    capacity,
                    joinable,
                }));
            }
            Ok(Err(e)) => {
                self.client
                    .matchmaking()
                    .leave_lobby(LobbyId::from_raw(lobby_id));
                debug_log("lobby_create_tunnel_fail", format!("lobby={lobby_id} err={e}"));
                let _ = reply.send(Err(e));
            }
            Err(_) => {
                self.client
                    .matchmaking()
                    .leave_lobby(LobbyId::from_raw(lobby_id));
                let _ = reply.send(Err("Steam 组网启动异常，已取消创建".to_string()));
            }
        }
    }

    fn on_lobby_joined(&mut self, res: Result<u64, String>) {
        let Some(pending) = self.pending_lobby.take() else {
            return;
        };
        let LobbyReply::One(reply) = pending.reply else {
            return;
        };
        let lobby_id = match res {
            Ok(id) => id,
            Err(e) => {
                debug_log("lobby_join_fail", format!("err={e}"));
                self.message = e.clone();
                let _ = reply.send(Err(e));
                return;
            }
        };
        let lid = LobbyId::from_raw(lobby_id);
        let mm = self.client.matchmaking();
        let pairs = read_lobby_pairs(&mm, lid);
        let players = mm.lobby_member_count(lid) as u32;
        let capacity = mm.lobby_member_limit(lid).unwrap_or(0) as u32;
        let owner = mm.lobby_owner(lid).raw().to_string();
        let Some(snapshot) = lobby::parse_snapshot(lobby_id, &pairs, players, capacity, &owner)
        else {
            mm.leave_lobby(lid);
            debug_log(
                "lobby_join_reject",
                format!("lobby={lobby_id} reason=missing_meta pairs={}", pairs.len()),
            );
            let _ = reply.send(Err(
                "房间信息不完整（缺少 ag_game / ag_ver / ag_gate），已取消加入".to_string()
            ));
            return;
        };
        let (game_id, join_token, nickname) = match pending.op {
            LobbyOp::Peek { .. } => {
                // 只读元数据：邀请链接不知道游戏标识，只校验协议版本。
                if snapshot.version != lobby::PROTOCOL_VERSION {
                    mm.leave_lobby(lid);
                    let _ = reply.send(Err(format!(
                        "房间协议版本 {} 与本机 {} 不一致",
                        snapshot.version,
                        lobby::PROTOCOL_VERSION
                    )));
                    return;
                }
                mm.leave_lobby(lid);
                debug_log(
                    "lobby_peek_ok",
                    format!(
                        "lobby={lobby_id} game={} gate={} players={}/{}",
                        snapshot.game_id,
                        snapshot.gate.as_str(),
                        snapshot.players,
                        snapshot.capacity
                    ),
                );
                let _ = reply.send(Ok(lobby_info(&snapshot)));
                return;
            }
            LobbyOp::Join {
                game_id,
                join_token,
                nickname,
            } => (game_id, join_token, nickname),
            _ => {
                mm.leave_lobby(lid);
                return;
            }
        };
        // 搜索进房时游戏标识已知，必须校验；邀请进房时为空，跳过。
        if !game_id.is_empty() {
            if let Err(e) = lobby::validate(&snapshot, &game_id) {
                mm.leave_lobby(lid);
                debug_log(
                    "lobby_join_reject",
                    format!(
                        "lobby={lobby_id} reason={e} game={} ver={}",
                        snapshot.game_id, snapshot.version
                    ),
                );
                let _ = reply.send(Err(format!("无法加入房间：{e}")));
                return;
            }
        }
        let host_steam_id = snapshot.host_steam_id.clone();
        let mut info = lobby_info(&snapshot);
        let (tx, mut rx) = oneshot::channel();
        self.start_room(false, host_steam_id, join_token, nickname, tx);
        match rx.try_recv() {
            Ok(Ok(room)) => {
                self.lobby_id = Some(lobby_id);
                self.game_id = game_id;
                info.players = room.member_count.max(1);
                let host = info.host_steam_id.clone();
                debug_log("lobby_join_ok", format!("lobby={lobby_id} host={host}"));
                let _ = reply.send(Ok(info));
            }
            Ok(Err(e)) => {
                mm.leave_lobby(lid);
                let _ = reply.send(Err(e));
            }
            Err(_) => {
                // 隧道还在握手（WELCOME 未到）：把回执接过来，每个 tick 检查。
                self.lobby_id = Some(lobby_id);
                self.game_id = game_id;
                self.lobby_forward = Some(LobbyForward {
                    rx,
                    reply: Some(reply),
                    info,
                });
            }
        }
    }

    fn on_lobby_listed(&mut self, res: Result<Vec<u64>, String>) {
        let Some(PendingLobby {
            op: LobbyOp::Search { game_id },
            reply: LobbyReply::Many(reply),
            ..
        }) = self.pending_lobby.take()
        else {
            return;
        };
        let ids = match res {
            Ok(ids) => ids,
            Err(e) => {
                // Steam 回调抖动时回放 TTL 内的旧结果，避免列表瞬间清空。
                let cached = self.lobby_cache.fresh(Instant::now());
                debug_log(
                    "lobby_search_fallback",
                    format!("err={e} cached={}", cached.len()),
                );
                let _ = reply.send(Err(if cached.is_empty() {
                    e
                } else {
                    format!("{e}（下方为上次搜索的缓存结果）")
                }));
                return;
            }
        };
        let raw_count = ids.len();
        let mm = self.client.matchmaking();
        let mut kept: Vec<LobbySnapshot> = Vec::new();
        for id in ids {
            if id == 0 || Some(id) == self.lobby_id {
                continue;
            }
            let lid = LobbyId::from_raw(id);
            let pairs = read_lobby_pairs(&mm, lid);
            let players = mm.lobby_member_count(lid) as u32;
            let capacity = mm.lobby_member_limit(lid).unwrap_or(0) as u32;
            let owner = mm.lobby_owner(lid).raw().to_string();
            let Some(snapshot) = lobby::parse_snapshot(id, &pairs, players, capacity, &owner)
            else {
                debug_log("lobby_skip", format!("lobby={id} reason=missing_meta"));
                continue;
            };
            if let Err(e) = lobby::validate(&snapshot, &game_id) {
                debug_log(
                    "lobby_skip",
                    format!(
                        "lobby={id} reason={e} game={} ver={}",
                        snapshot.game_id, snapshot.version
                    ),
                );
                continue;
            }
            if capacity > 0 && players >= capacity {
                debug_log("lobby_skip", format!("lobby={id} reason=full"));
                continue;
            }
            kept.push(snapshot);
        }
        debug_log(
            "lobby_search_ok",
            format!(
                "game={game_id} raw={raw_count} kept={} ids={:?}",
                kept.len(),
                kept.iter().map(|s| s.lobby_id).collect::<Vec<_>>()
            ),
        );
        let out: Vec<SteamLobbyInfo> = kept.iter().map(lobby_info).collect();
        self.lobby_cache.replace(kept, Instant::now());
        let _ = reply.send(Ok(out));
    }

    /// 客人侧：等隧道握手完成再把大厅 API 的回执发出去。
    fn poll_lobby_forward(&mut self) {
        let Some(mut fwd) = self.lobby_forward.take() else {
            return;
        };
        match fwd.rx.try_recv() {
            Ok(Ok(room)) => {
                let mut info = fwd.info.clone();
                info.players = room.member_count.max(1);
                debug_log("lobby_join_tunnel_ok", format!("lobby={}", info.lobby_id));
                if let Some(reply) = fwd.reply.take() {
                    let _ = reply.send(Ok(info));
                }
            }
            Ok(Err(e)) => {
                debug_log("lobby_join_tunnel_fail", format!("err={e}"));
                if let Some(reply) = fwd.reply.take() {
                    let _ = reply.send(Err(e));
                }
            }
            Err(oneshot::error::TryRecvError::Empty) => {
                self.lobby_forward = Some(fwd);
            }
            Err(oneshot::error::TryRecvError::Closed) => {
                if let Some(reply) = fwd.reply.take() {
                    let _ = reply.send(Err("Steam 组网已取消".to_string()));
                }
            }
        }
    }

    fn start_room(
        &mut self,
        host: bool,
        host_steam_id: String,
        join_token: String,
        nickname: String,
        reply: oneshot::Sender<Result<SteamRoomInfo, String>>,
    ) {
        self.shutdown_room("重新开始 Steam 组网");
        self.nickname = if nickname.trim().is_empty() {
            self.persona.clone()
        } else {
            nickname.trim().to_string()
        };
        self.join_token = join_token;
        self.rx_bytes = 0;
        self.tx_bytes = 0;
        self.drops = 0;

        if host {
            self.role = Role::Host;
            self.my_vip = proto::HOST_VIP;
            self.my_peer_id = 1;
            let tun = match tun::open(proto::HOST_VIP, proto::MTU) {
                Ok(t) => t,
                Err(e) => {
                    self.role = Role::Idle;
                    let _ = reply.send(Err(e.clone()));
                    self.message = e;
                    return;
                }
            };
            self.tun = Some(tun);
            match self
                .sockets
                .create_listen_socket_p2p(CONTROL_VPORT_CACHE, vec![])
            {
                Ok(ls) => self.listen = Some(ls),
                Err(e) => {
                    self.shutdown_room("创建 Steam 监听失败");
                    let msg = format!("创建 Steam P2P 监听失败: {e:?}");
                    let _ = reply.send(Err(msg.clone()));
                    self.message = msg;
                    return;
                }
            }
            self.members.insert(
                self.self_steam_id,
                Member {
                    peer_id: 1,
                    steam_id: self.self_steam_id,
                    nickname: self.nickname.clone(),
                    vip: proto::HOST_VIP,
                    online: true,
                    is_host: true,
                    latency_ms: 0,
                    via_relay: false,
                    bytes_in: 0,
                    bytes_out: 0,
                    last_seen: Instant::now(),
                    offline_since: None,
                },
            );
            self.message = "Steam 房间已开启，等待成员加入".to_string();
            self.publish(true);
            let _ = reply.send(Ok(room_info()));
            return;
        }

        // 客人：先连房主，拿到 Welcome 再建网卡（需要分配到的虚拟 IP）。
        let host_id = match host_steam_id.trim().parse::<u64>() {
            Ok(v) => v,
            Err(_) => {
                let msg = format!("无效的房主 SteamID: {host_steam_id}");
                self.role = Role::Idle;
                let _ = reply.send(Err(msg.clone()));
                self.message = msg;
                return;
            }
        };
        self.role = Role::Guest;
        self.host_steam_id = host_id;
        self.start_reply = Some(reply);
        self.start_deadline = Some(Instant::now() + START_TIMEOUT);
        self.message = "正在连接 Steam 房主…".to_string();
        self.connect_to_host();
        self.publish(true);
    }

    fn connect_to_host(&mut self) {
        if self.host_steam_id == 0 {
            return;
        }
        let identity = NetworkingIdentity::new_steam_id(SteamId::from_raw(self.host_steam_id));
        match self
            .sockets
            .connect_p2p(identity, CONTROL_VPORT_CACHE, vec![])
        {
            Ok(conn) => {
                self.host_conn = Some(conn);
                self.host_via_relay = false;
                self.hello_sent = false;
                self.reconnect_at = None;
            }
            Err(e) => {
                debug_log(
                    "connect_fail",
                    format!("host={} err={e:?}", self.host_steam_id),
                );
                self.message = format!("连接 Steam 房主失败: {e:?}");
                self.reconnect_at = Some(Instant::now() + RECONNECT_DELAY);
            }
        }
    }

    fn shutdown_room(&mut self, reason: &str) {
        debug_log("shutdown_room", format!("reason={reason}"));
        // 先让自己从搜索结果里消失，再真正离开；否则别人还会看到一间
        // 已经没人的幽灵房，直到 Steam 自己清理。
        if let Some(lobby_id) = self.lobby_id.take() {
            let lid = LobbyId::from_raw(lobby_id);
            let mm = self.client.matchmaking();
            let hidden = mm.set_lobby_joinable(lid, false);
            self.lobby_joinable = false;
            mm.leave_lobby(lid);
            debug_log(
                "lobby_leave",
                format!("lobby={lobby_id} set_joinable_false={hidden}"),
            );
        }
        if let Some(tun) = self.tun.take() {
            tun.shutdown();
        }
        self.host_conn = None;
        self.conns.clear();
        self.listen = None;
        self.members.clear();
        self.roster.clear();
        self.guest_offline_since.clear();
        self.pending.clear();
        self.inbound_replies.clear();
        self.batch_up.clear();
        self.batch_flood.clear();
        self.my_vip = Ipv4Addr::UNSPECIFIED;
        self.my_peer_id = 0;
        self.host_steam_id = 0;
        self.host_via_relay = false;
        self.hello_sent = false;
        self.reconnect_at = None;
        self.start_deadline = None;
        self.role = Role::Idle;
        INVITE_DIALOG_CALLED.store(false, Ordering::Relaxed);
        if let Some(tx) = self.start_reply.take() {
            let _ = tx.send(Err(reason.to_string()));
        }
        self.message = reason.to_string();
        update_status(|s| {
            s.room_active = false;
            s.is_host = false;
            s.virtual_ip.clear();
            s.member_count = 0;
            s.message = reason.to_string();
        });
        publish_room(SteamRoomInfo::default());
        // 房间结束：关闭入站订阅，避免 Dart 侧旧订阅的 cancel() 永远挂起。
        close_app_inbound();
    }

    fn tick(&mut self) {
        self.client.run_callbacks();
        // 大厅回调必须在 run_callbacks 之后立刻回收，避免结果积压一整个 tick。
        self.poll_lobby_events();
        self.poll_lobby_forward();
        self.poll_relay();
        self.poll_listener();
        self.poll_tun();
        self.poll_connections();
        self.refresh_relay();
        self.flush_out_batches();
        self.heartbeat();
        self.check_deadlines();
        self.prune();
        self.publish(false);
    }

    fn poll_relay(&mut self) {
        // 不只在启动时判定一次：Steam 掉线 / 中继网络断开后要继续显示真实状态。
        if self.last_ready_check.elapsed() < Duration::from_secs(2) {
            return;
        }
        self.last_ready_check = Instant::now();
        let ready = self
            .client
            .networking_utils()
            .detailed_relay_network_status()
            .availability()
            == Ok(NetworkingAvailability::Current);
        if ready == self.relay_ready {
            return;
        }
        self.relay_ready = ready;
        update_status(|s| {
            s.relay_ready = ready;
            if ready {
                // 只覆盖中继相关的提示，别把房间 / 成员消息冲掉。
                if s.message.starts_with("已连接 Steam")
                    || s.message.starts_with("SDR 中继")
                    || s.message.starts_with("正在获取中继")
                {
                    s.message = "SDR 中继网络已就绪".to_string();
                }
            } else {
                s.message = "SDR 中继网络已断开，正在重连…".to_string();
            }
        });
    }

    fn poll_listener(&mut self) {
        let mut events = Vec::new();
        if let Some(listen) = self.listen.as_ref() {
            while let Some(ev) = listen.try_receive_event() {
                events.push(ev);
            }
        }
        for event in events {
            match event {
                ListenSocketEvent::Connecting(req) => {
                    let _ = req.accept();
                }
                ListenSocketEvent::Connected(ev) => {
                    let steam_id = ev.remote().steam_id().map(|s| s.raw()).unwrap_or(0);
                    let conn = ev.take_connection();
                    if steam_id != 0 {
                        self.conns.insert(steam_id, conn);
                        self.message = "新的 Steam 连接已接入".to_string();
                    }
                }
                ListenSocketEvent::Disconnected(ev) => {
                    let steam_id = ev.remote().steam_id().map(|s| s.raw()).unwrap_or(0);
                    self.remove_member(steam_id, "成员已断开");
                }
            }
        }
    }

    fn remove_member(&mut self, steam_id: u64, reason: &str) {
        if steam_id == 0 {
            return;
        }
        self.conns.remove(&steam_id);
        if let Some(m) = self.members.get_mut(&steam_id) {
            if m.online {
                m.offline_since = Some(Instant::now());
            }
            m.online = false;
            m.last_seen = Instant::now();
        }
        self.message = reason.to_string();
        debug_log(
            "member_offline",
            format!(
                "sid={steam_id} reason={reason} retained={} total={}",
                self.members.contains_key(&steam_id),
                self.members.len()
            ),
        );
        if self.role == Role::Host {
            self.broadcast_roster();
        }
    }

    fn poll_tun(&mut self) {
        let Some(tun) = self.tun.as_ref() else {
            return;
        };
        let mut packets = Vec::new();
        loop {
            match tun.rx.try_recv() {
                Ok(p) => packets.push(p),
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => break,
            }
        }
        for packet in packets {
            self.route_ip_out(&packet);
        }
    }

    fn route_ip_out(&mut self, packet: &[u8]) {
        let Some(dst) = proto::ipv4_dst(packet) else {
            self.drops += 1;
            return;
        };
        if proto::is_broadcast(dst) || proto::is_multicast(dst) {
            self.batch_flood.extend_from_slice(packet);
            if self.batch_flood.len() >= proto::MAX_BATCH_BYTES {
                let flood = std::mem::take(&mut self.batch_flood);
                self.send_ip_frame(proto::BROADCAST_VIP, proto::FLAG_FLOOD, &flood);
            }
            return;
        }
        if dst == self.my_vip {
            return;
        }
        if !proto::is_room_vip(dst) {
            self.drops += 1;
            return;
        }
        let entry = self.batch_up.entry(dst).or_default();
        entry.extend_from_slice(packet);
        if entry.len() >= proto::MAX_BATCH_BYTES {
            // 单帧上限：先把这个目标的缓冲取出来清空，再整批发出去。
            let data = std::mem::take(entry);
            self.send_ip_frame(dst, 0, &data);
        }
    }

    fn flush_out_batches(&mut self) {
        let uni = std::mem::take(&mut self.batch_up);
        let flood = std::mem::take(&mut self.batch_flood);
        for (dst, data) in uni {
            if data.is_empty() {
                continue;
            }
            self.send_ip_frame(dst, 0, &data);
        }
        if !flood.is_empty() {
            self.send_ip_frame(proto::BROADCAST_VIP, proto::FLAG_FLOOD, &flood);
        }
    }

    fn send_ip_frame(&mut self, dst: Ipv4Addr, flags: u8, payload: &[u8]) {
        let bytes = proto::encode(proto::KIND_IP, flags, self.my_vip, dst, payload);
        match self.role {
            Role::Guest => {
                self.send_to_host(&bytes, SendFlags::UNRELIABLE_NO_NAGLE);
            }
            Role::Host => {
                if flags & proto::FLAG_FLOOD != 0 {
                    self.send_to_all(&bytes, SendFlags::UNRELIABLE_NO_NAGLE, None);
                } else if let Some(sid) = self.steam_id_of_vip(dst) {
                    self.send_to_steam(sid, &bytes, SendFlags::UNRELIABLE_NO_NAGLE);
                } else {
                    self.drops += 1;
                }
            }
            Role::Idle => {}
        }
    }

    fn send_to_host(&mut self, bytes: &[u8], flags: SendFlags) -> bool {
        let Some(conn) = self.host_conn.as_ref() else {
            return false;
        };
        match conn.send_message(bytes, flags) {
            Ok(_) => {
                self.tx_bytes += bytes.len() as u64;
                true
            }
            Err(_) => false,
        }
    }

    fn send_to_steam(&mut self, steam_id: u64, bytes: &[u8], flags: SendFlags) -> bool {
        let Some(conn) = self.conns.get(&steam_id) else {
            return false;
        };
        match conn.send_message(bytes, flags) {
            Ok(_) => {
                self.tx_bytes += bytes.len() as u64;
                if let Some(m) = self.members.get_mut(&steam_id) {
                    m.bytes_out += bytes.len() as u64;
                }
                true
            }
            Err(_) => false,
        }
    }

    fn send_to_all(&mut self, bytes: &[u8], flags: SendFlags, exclude: Option<u64>) {
        let ids: Vec<u64> = self
            .conns
            .keys()
            .copied()
            .filter(|id| Some(*id) != exclude)
            .collect();
        for id in ids {
            self.send_to_steam(id, bytes, flags);
        }
    }

    fn poll_connections(&mut self) {
        let mut inbound: Vec<(u64, Vec<u8>)> = Vec::new();
        let mut closed: Vec<u64> = Vec::new();

        if self.role == Role::Host {
            for (steam_id, conn) in self.conns.iter_mut() {
                let mut is_closed = false;
                if let Ok(info) = conn.info() {
                    if let Ok(state) = info.state() {
                        if is_dead_state(state) {
                            is_closed = true;
                        }
                    }
                }
                if is_closed {
                    closed.push(*steam_id);
                    continue;
                }
                if let Ok(messages) = conn.receive_messages(32) {
                    for msg in messages {
                        inbound.push((*steam_id, msg.data().to_vec()));
                    }
                }
            }
        }

        let mut host_closed = false;
        let mut host_msgs: Vec<Vec<u8>> = Vec::new();
        if self.role == Role::Guest {
            if let Some(conn) = self.host_conn.as_mut() {
                if let Ok(info) = conn.info() {
                    if let Ok(state) = info.state() {
                        if is_dead_state(state) {
                            host_closed = true;
                        }
                    }
                }
                if !host_closed {
                    if let Ok(messages) = conn.receive_messages(32) {
                        for msg in messages {
                            host_msgs.push(msg.data().to_vec());
                        }
                    }
                }
            }
        }

        for steam_id in closed {
            self.remove_member(steam_id, "成员连接已关闭");
        }
        if host_closed {
            debug_log("host_closed", format!("host={}", self.host_steam_id));
            self.host_conn = None;
            self.host_via_relay = false;
            self.hello_sent = false;
            self.message = "与房主的连接已断开，正在重连…".to_string();
            // 房主链路断开后 Roster 已失效：清空成员表并立即发布，
            // 避免 UI 继续显示过期成员，也让 Dart 侧能判定房主离线。
            self.roster.clear();
            self.guest_ping_at = None;
            self.guest_host_latency_ms = 0;
            self.publish(true);
            self.reconnect_at = Some(Instant::now() + RECONNECT_DELAY);
        }

        for (steam_id, data) in inbound {
            if let Some(m) = self.members.get_mut(&steam_id) {
                m.bytes_in += data.len() as u64;
                m.last_seen = Instant::now();
            }
            self.rx_bytes += data.len() as u64;
            self.handle_message(steam_id, &data);
        }

        let host_id = self.host_steam_id;
        for data in host_msgs {
            self.rx_bytes += data.len() as u64;
            self.handle_message(host_id, &data);
        }
    }

    /// 读取 Steam 连接的真实路径（中继 / 直连）。
    ///
    /// `SteamNetConnectionInfo_t.m_idPOPRelay` 非 0 表示走 SDR 中继；为 0 说明是
    /// 两端直连（含同机虚拟连接）。只在连接进入 Connected 后取值，避免握手阶段
    /// 误报成直连。
    fn refresh_relay(&mut self) {
        if self.last_relay_check.elapsed() < Duration::from_secs(1) {
            return;
        }
        self.last_relay_check = Instant::now();
        match self.role {
            Role::Host => {
                for (steam_id, conn) in self.conns.iter() {
                    let Ok(info) = conn.info() else {
                        continue;
                    };
                    if !matches!(info.state(), Ok(NetworkingConnectionState::Connected)) {
                        continue;
                    }
                    let via_relay = info.relay_pop() != 0;
                    if let Some(m) = self.members.get_mut(steam_id) {
                        m.via_relay = via_relay;
                    }
                }
            }
            Role::Guest => {
                let Some(conn) = self.host_conn.as_ref() else {
                    return;
                };
                let Ok(info) = conn.info() else {
                    return;
                };
                if matches!(info.state(), Ok(NetworkingConnectionState::Connected)) {
                    self.host_via_relay = info.relay_pop() != 0;
                }
            }
            Role::Idle => {}
        }
    }

    fn handle_message(&mut self, from_steam: u64, data: &[u8]) {
        let Some(frame) = proto::decode(data) else {
            return;
        };
        match frame.kind {
            proto::KIND_IP => self.on_ip(from_steam, &frame),
            proto::KIND_CONTROL => self.on_control(from_steam, &frame),
            proto::KIND_RPC => self.on_rpc(from_steam, &frame),
            _ => {}
        }
    }

    fn on_ip(&mut self, from_steam: u64, frame: &Frame<'_>) {
        if frame.payload.is_empty() {
            return;
        }
        let flooded = frame.flags & proto::FLAG_FLOOD != 0;
        if flooded && self.seen_recently(frame) {
            return;
        }
        match self.role {
            Role::Guest => {
                if let Some(tun) = self.tun.as_ref() {
                    for packet in proto::split_ipv4(frame.payload) {
                        if !tun.inject(packet) {
                            self.drops += 1;
                        }
                    }
                }
            }
            Role::Host => {
                if flooded {
                    if let Some(tun) = self.tun.as_ref() {
                        for packet in proto::split_ipv4(frame.payload) {
                            let _ = tun.inject(packet);
                        }
                    }
                    let bytes = proto::encode(
                        proto::KIND_IP,
                        frame.flags,
                        frame.src,
                        frame.dst,
                        frame.payload,
                    );
                    self.send_to_all(&bytes, SendFlags::UNRELIABLE_NO_NAGLE, Some(from_steam));
                } else if frame.dst == proto::HOST_VIP {
                    if let Some(tun) = self.tun.as_ref() {
                        for packet in proto::split_ipv4(frame.payload) {
                            let _ = tun.inject(packet);
                        }
                    }
                } else if let Some(sid) = self.steam_id_of_vip(frame.dst) {
                    let bytes = proto::encode(
                        proto::KIND_IP,
                        frame.flags,
                        frame.src,
                        frame.dst,
                        frame.payload,
                    );
                    self.send_to_steam(sid, &bytes, SendFlags::UNRELIABLE_NO_NAGLE);
                } else {
                    self.drops += 1;
                }
            }
            Role::Idle => {}
        }
    }

    fn on_control(&mut self, from_steam: u64, frame: &Frame<'_>) {
        let Some(kind) = proto::control_kind(frame.payload) else {
            return;
        };
        match kind {
            proto::CTL_HELLO => {
                if self.role != Role::Host {
                    return;
                }
                let Some(hello) = proto::parse_hello(frame.payload) else {
                    return;
                };
                debug_log(
                    "hello_recv",
                    format!(
                        "sid={from_steam} ver={} game={}",
                        hello.version, hello.game_id
                    ),
                );
                let game_matches = self.game_id.is_empty()
                    || hello.game_id.eq_ignore_ascii_case(&self.game_id);
                if hello.token != self.join_token
                    || hello.steam_id != from_steam
                    || !game_matches
                {
                    debug_log(
                        "hello_reject",
                        format!(
                            "sid={from_steam} token_match={} id_match={} game_match={game_matches} \
                             guest_game={} host_game={}",
                            hello.token == self.join_token,
                            hello.steam_id == from_steam,
                            hello.game_id,
                            self.game_id
                        ),
                    );
                    let body = proto::kick(if game_matches {
                        "房间密码不匹配"
                    } else {
                        "游戏标识不一致，无法加入该房间"
                    });
                    let bytes = proto::encode(
                        proto::KIND_CONTROL,
                        0,
                        proto::HOST_VIP,
                        proto::BROADCAST_VIP,
                        &body,
                    );
                    self.send_to_steam(from_steam, &bytes, SendFlags::RELIABLE);
                    debug_log(
                        "kick_sent",
                        format!(
                            "sid={from_steam} reason={}",
                            if game_matches {
                                "房间密码不匹配"
                            } else {
                                "游戏标识不一致"
                            }
                        ),
                    );
                    self.remove_member(from_steam, "成员鉴权失败");
                    return;
                }
                let (peer_id, vip) = self.assign_member(from_steam);
                debug_log(
                    "hello_ok",
                    format!("sid={from_steam} peer={peer_id} vip={vip}"),
                );
                self.members.insert(
                    from_steam,
                    Member {
                        peer_id,
                        steam_id: from_steam,
                        nickname: if hello.nickname.trim().is_empty() {
                            format!("Steam 用户 {}", from_steam % 100000)
                        } else {
                            hello.nickname
                        },
                        vip,
                        online: true,
                        is_host: false,
                        latency_ms: 0,
                        via_relay: false,
                        bytes_in: 0,
                        bytes_out: 0,
                        last_seen: Instant::now(),
                        offline_since: None,
                    },
                );
                let welcome = proto::WelcomeMsg {
                    vip,
                    host_vip: proto::HOST_VIP,
                    peer_id,
                    network: "100.100.100.0/24".to_string(),
                    mtu: proto::MTU as u16,
                };
                let body = proto::welcome(&welcome);
                let bytes = proto::encode(proto::KIND_CONTROL, 0, proto::HOST_VIP, vip, &body);
                self.send_to_steam(from_steam, &bytes, SendFlags::RELIABLE);
                debug_log(
                    "welcome_sent",
                    format!("sid={from_steam} peer={peer_id} vip={vip}"),
                );
                self.message = "成员已加入房间".to_string();
                self.broadcast_roster();
            }
            proto::CTL_WELCOME => {
                if self.role != Role::Guest {
                    return;
                }
                let Some(welcome) = proto::parse_welcome(frame.payload) else {
                    return;
                };
                self.my_vip = welcome.vip;
                self.my_peer_id = welcome.peer_id;
                if self.tun.is_none() {
                    match tun::open(welcome.vip, proto::MTU) {
                        Ok(t) => self.tun = Some(t),
                        Err(e) => {
                            let msg = format!("创建虚拟网卡失败: {e}");
                            self.shutdown_room(&msg);
                            return;
                        }
                    }
                }
                self.message = format!("已加入 Steam 房间，本机虚拟 IP {}", welcome.vip);
                debug_log(
                    "welcome",
                    format!(
                        "peer={} vip={} host={}",
                        welcome.peer_id, welcome.vip, self.host_steam_id
                    ),
                );
                self.start_deadline = None;
                self.publish(true);
                if let Some(tx) = self.start_reply.take() {
                    let _ = tx.send(Ok(room_info()));
                }
            }
            proto::CTL_ROSTER => {
                if let Some(entries) = proto::parse_roster(frame.payload) {
                    self.roster = entries;
                    if self.role == Role::Guest {
                        let now = Instant::now();
                        // 只对普通成员做本地离线计时：房主条目代表房间本身，
                        // 房主断开由 host_closed 处理，不在这里过滤。
                        for entry in &self.roster {
                            if entry.is_host || entry.online {
                                self.guest_offline_since.remove(&entry.steam_id);
                            } else {
                                self.guest_offline_since
                                    .entry(entry.steam_id)
                                    .or_insert(now);
                            }
                        }
                        // 房主不知道本机↔房主的 RTT，Roster 里房主条目恒为 0；
                        // 用客机自己测到的值回填，避免每 5s 被刷回 0ms。
                        for entry in self.roster.iter_mut().filter(|e| e.is_host) {
                            entry.latency_ms = self.guest_host_latency_ms;
                        }
                    }
                }
            }
            proto::CTL_PING => {
                let bytes = proto::encode(
                    proto::KIND_CONTROL,
                    0,
                    self.my_vip,
                    frame.src,
                    &proto::simple_control(proto::CTL_PONG),
                );
                self.send_frame_to_vip(frame.src, &bytes, SendFlags::RELIABLE);
            }
            proto::CTL_PONG => {
                let now = Instant::now();
                if let Some(m) = self.members.get_mut(&from_steam) {
                    m.last_seen = now;
                }
                if self.role == Role::Guest && from_steam == self.host_steam_id {
                    if let Some(sent_at) = self.guest_ping_at.take() {
                        let ms = now
                            .duration_since(sent_at)
                            .as_millis()
                            .min(u32::MAX as u128) as u32;
                        self.guest_host_latency_ms = ms;
                        for entry in self.roster.iter_mut().filter(|e| e.is_host) {
                            entry.latency_ms = ms;
                        }
                    }
                }
            }
            proto::CTL_KICK => {
                if self.role == Role::Guest {
                    let reason = proto::kick_reason(frame.payload);
                    let reason = if reason.is_empty() {
                        "已被房主移出房间".to_string()
                    } else {
                        format!("已被房主移出房间：{reason}")
                    };
                    debug_log("kick", format!("from={from_steam} reason={reason}"));
                    self.shutdown_room(&reason);
                }
            }
            proto::CTL_BYE => {
                if self.role == Role::Guest {
                    let reason = proto::kick_reason(frame.payload);
                    debug_log("bye", format!("from={from_steam} reason={reason}"));
                    self.shutdown_room(if reason.is_empty() {
                        "房主已关闭房间"
                    } else {
                        &reason
                    });
                } else {
                    debug_log("bye", format!("sid={from_steam} role=host"));
                    self.remove_member(from_steam, "成员已离开");
                }
            }
            _ => {}
        }
    }

    fn on_rpc(&mut self, _from_steam: u64, frame: &Frame<'_>) {
        if self.role == Role::Host && frame.dst != proto::HOST_VIP {
            if let Some(sid) = self.steam_id_of_vip(frame.dst) {
                let bytes = proto::encode(proto::KIND_RPC, 0, frame.src, frame.dst, frame.payload);
                self.send_to_steam(sid, &bytes, SendFlags::RELIABLE);
            }
            return;
        }
        self.handle_rpc_local(frame);
    }

    fn handle_rpc_local(&mut self, frame: &Frame<'_>) {
        if let Some((op, call)) = proto::parse_rpc_call(frame.payload) {
            // 只处理 call / notify；reply / ping 的载荷也能被 parse_rpc_call 勉强解出来，
            // 所以必须先按 op 过滤，否则回包会被误当成入站调用。
            match op {
                proto::RPC_CALL => {
                    self.next_token += 1;
                    let token = self.next_token;
                    self.inbound_replies
                        .insert(token, (frame.src, call.request_id));
                    emit_inbound(AppInboundEventC {
                        kind: AppInboundKindC::Call,
                        from_peer_id: self.peer_id_of_vip(frame.src).unwrap_or(0),
                        channel: call.channel,
                        request_id: call.request_id,
                        token,
                        payload: call.payload,
                    });
                }
                proto::RPC_NOTIFY => {
                    emit_inbound(AppInboundEventC {
                        kind: AppInboundKindC::Notify,
                        from_peer_id: self.peer_id_of_vip(frame.src).unwrap_or(0),
                        channel: call.channel,
                        request_id: 0,
                        token: 0,
                        payload: call.payload,
                    });
                }
                _ => {}
            }
            if op == proto::RPC_CALL || op == proto::RPC_NOTIFY {
                return;
            }
        }

        if let Some(reply) = proto::parse_rpc_reply(frame.payload) {
            if let Some(PendingEntry {
                kind: PendingKind::Call(tx),
                ..
            }) = self.pending.remove(&reply.request_id)
            {
                let _ = tx.send(Ok(AppCallResultC {
                    status: reply.status,
                    error_msg: reply.error_msg,
                    payload: reply.payload,
                }));
            }
            return;
        }

        if let Some(nonce) = proto::parse_rpc_ping(frame.payload) {
            if let Some(PendingEntry {
                kind: PendingKind::Ping(tx),
                at,
            }) = self.pending.remove(&nonce)
            {
                let rtt = at.elapsed().as_millis() as u64;
                let _ = tx.send(Ok(rtt));
            } else {
                // 不是自己的请求 → 这是对端发来的 ping，原样回一个。
                let body = proto::rpc_ping(nonce);
                self.send_rpc_frame(frame.src, &body);
            }
        }
    }

    fn do_app_call(
        &mut self,
        dst_peer_id: u32,
        channel: String,
        request_id: u64,
        payload: Vec<u8>,
        flags: u32,
        reply: oneshot::Sender<Result<AppCallResultC, String>>,
    ) {
        let Some(vip) = self.vip_for_peer(dst_peer_id) else {
            let _ = reply.send(Err(format!("成员 {dst_peer_id} 不在房间内")));
            return;
        };
        let rid = if request_id != 0 {
            request_id
        } else {
            self.next_request += 1;
            self.next_request
        };
        self.pending.insert(
            rid,
            PendingEntry {
                kind: PendingKind::Call(reply),
                at: Instant::now(),
            },
        );
        let body = proto::rpc_call(
            proto::RPC_CALL,
            &proto::RpcCall {
                request_id: rid,
                flags,
                channel,
                payload,
            },
        );
        if !self.send_rpc_frame(vip, &body) {
            if let Some(PendingEntry {
                kind: PendingKind::Call(tx),
                ..
            }) = self.pending.remove(&rid)
            {
                let _ = tx.send(Err("发送失败：房间连接不可用".to_string()));
            }
        }
    }

    fn send_rpc_frame(&mut self, dst_vip: Ipv4Addr, body: &[u8]) -> bool {
        let bytes = proto::encode(proto::KIND_RPC, 0, self.my_vip, dst_vip, body);
        self.send_frame_to_vip(dst_vip, &bytes, SendFlags::RELIABLE)
    }

    fn send_frame_to_vip(&mut self, dst_vip: Ipv4Addr, bytes: &[u8], flags: SendFlags) -> bool {
        match self.role {
            Role::Guest => self.send_to_host(bytes, flags),
            Role::Host => {
                if dst_vip == proto::HOST_VIP {
                    false
                } else if let Some(sid) = self.steam_id_of_vip(dst_vip) {
                    self.send_to_steam(sid, bytes, flags)
                } else {
                    false
                }
            }
            Role::Idle => false,
        }
    }

    fn heartbeat(&mut self) {
        if self.role == Role::Idle {
            return;
        }
        if self.role == Role::Guest && self.host_conn.is_none() {
            if self
                .reconnect_at
                .map(|at| Instant::now() >= at)
                .unwrap_or(true)
            {
                self.reconnect_at = Some(Instant::now() + RECONNECT_DELAY);
                self.connect_to_host();
            }
            return;
        }
        if self.role == Role::Guest && !self.hello_sent && self.host_conn.is_some() {
            let body = proto::hello(&proto::HelloMsg {
                token: self.join_token.clone(),
                steam_id: self.self_steam_id,
                nickname: self.nickname.clone(),
                version: proto::VERSION.to_string(),
                game_id: self.game_id.clone(),
            });
            let bytes = proto::encode(
                proto::KIND_CONTROL,
                0,
                Ipv4Addr::UNSPECIFIED,
                proto::HOST_VIP,
                &body,
            );
            if self.send_to_host(&bytes, SendFlags::RELIABLE) {
                self.hello_sent = true;
                debug_log("hello_sent", format!("host={}", self.host_steam_id));
            }
        }

        if self.last_heartbeat.elapsed() < HEARTBEAT {
            return;
        }
        self.last_heartbeat = Instant::now();
        let body = proto::simple_control(proto::CTL_PING);
        match self.role {
            Role::Host => {
                let bytes = proto::encode(
                    proto::KIND_CONTROL,
                    0,
                    proto::HOST_VIP,
                    proto::BROADCAST_VIP,
                    &body,
                );
                self.send_to_all(&bytes, SendFlags::RELIABLE, None);
                self.probe_latency();
            }
            Role::Guest => {
                self.guest_ping_at = Some(Instant::now());
                let bytes =
                    proto::encode(proto::KIND_CONTROL, 0, self.my_vip, proto::HOST_VIP, &body);
                self.send_to_host(&bytes, SendFlags::RELIABLE);
            }
            Role::Idle => {}
        }

        // 房主定期重发成员表，覆盖丢包与后加入的成员。
        if self.role == Role::Host && self.last_roster_at.elapsed() > Duration::from_secs(5) {
            self.broadcast_roster();
        }
    }

    fn probe_latency(&mut self) {
        if self.last_ping_probe.elapsed() < Duration::from_secs(2) {
            return;
        }
        self.last_ping_probe = Instant::now();
        let ids: Vec<u64> = self.conns.keys().copied().collect();
        for id in ids {
            if let Some(conn) = self.conns.get(&id) {
                if let Ok((info, _)) = self.sockets.get_realtime_connection_status(conn, 1) {
                    let ping = info.ping().max(0) as u32;
                    if let Some(m) = self.members.get_mut(&id) {
                        m.latency_ms = ping;
                    }
                }
            }
        }
    }

    fn check_deadlines(&mut self) {
        if self.role != Role::Guest {
            return;
        }
        if let Some(deadline) = self.start_deadline {
            if Instant::now() >= deadline {
                let msg = "连接房主超时：请确认对方已开启房间且 Steam 网络可用".to_string();
                debug_log("start_timeout", format!("host={}", self.host_steam_id));
                self.shutdown_room(&msg);
            }
        }
    }

    /// 诊断用：往真实成员表里塞一个「离线超过宽限期」的成员，然后调用真正的
    /// [`Engine::prune`]，观察它是否被摘除并广播。
    ///
    /// 只在 `ASTRAL_STEAM_DEBUG=1` 时由 Dart 侧按钮触发，正常流程不会调用。
    fn debug_ghost_probe(&mut self) -> Result<String, String> {
        if self.role != Role::Host {
            return Err("只有房主可以运行幽灵成员诊断".to_string());
        }
        if !*STEAM_DEBUG {
            return Err("需要 ASTRAL_STEAM_DEBUG=1 才能运行诊断".to_string());
        }
        let sid = 76561190000000001u64;
        let now = Instant::now();
        let before = self.members.len();
        let expired = now - roster_policy::OFFLINE_GRACE - Duration::from_secs(1);
        self.members.insert(
            sid,
            Member {
                peer_id: 9001,
                steam_id: sid,
                nickname: "ghost-test".to_string(),
                vip: Ipv4Addr::new(100, 100, 100, 254),
                online: false,
                is_host: false,
                latency_ms: 0,
                via_relay: false,
                bytes_in: 0,
                bytes_out: 0,
                last_seen: expired,
                offline_since: Some(expired),
            },
        );
        let injected = self.members.len();
        self.prune();
        self.publish(true);
        let after = self.members.len();
        let still_there = self.members.contains_key(&sid);
        debug_log(
            "debug_ghost_probe",
            format!("before={before} injected={injected} after={after} removed={}", !still_there),
        );
        if still_there {
            return Err(format!("诊断失败：成员仍在表中（{injected} -> {after}）"));
        }
        Ok(format!(
            "幽灵成员已摘除：成员数 {injected}（含注入）-> {after}，roster={}",
            self.roster.len()
        ))
    }

    /// 组网诊断快照：一次性给出大厅 id、`ag_*` 实读值、可加入状态、成员数与
    /// 覆盖层状态，双机验收时直接核对这些值。
    ///
    /// Steam 没有读取 joinable 的接口，这里回放本机最后一次写入的值。
    fn lobby_diag(&self) -> Result<SteamLobbyDiag, String> {
        let overlay = self.client.utils().is_overlay_enabled();
        let overlay_hint = if overlay {
            String::new()
        } else {
            "Steam 覆盖层未开启：原生邀请面板不可用，可用好友 SteamID 直接邀请或搜索房间"
                .to_string()
        };
        let ivid = INVITE_DIALOG_CALLED.load(Ordering::Relaxed);
        let Some(lobby_id) = self.lobby_id else {
            return Ok(SteamLobbyDiag {
                overlay_enabled: overlay,
                invite_dialog_called: ivid,
                overlay_hint,
                ..Default::default()
            });
        };
        let mm = self.client.matchmaking();
        let lid = LobbyId::from_raw(lobby_id);
        let game = mm.lobby_data(lid, lobby::KEY_GAME).unwrap_or_default();
        let version = mm.lobby_data(lid, lobby::KEY_VER).unwrap_or_default();
        let gate = mm.lobby_data(lid, lobby::KEY_GATE).unwrap_or_default();
        let members = mm.lobby_member_count(lid) as u32;
        let capacity = mm.lobby_member_limit(lid).unwrap_or(0) as u32;
        debug_log(
            "lobby_diag",
            format!(
                "lobby={lobby_id} game={game} ver={version} gate={gate} joinable={} \
                 members={members}/{capacity} overlay={overlay}",
                self.lobby_joinable
            ),
        );
        Ok(SteamLobbyDiag {
            lobby_id: lobby_id.to_string(),
            game_id: game,
            version,
            gate,
            joinable: self.lobby_joinable,
            members,
            capacity,
            is_host: self.role == Role::Host,
            overlay_enabled: overlay,
            invite_dialog_called: ivid,
            overlay_hint,
        })
    }

    /// 诊断用：把引擎临时切到客人分支，注入一个「房主已离线超过宽限期」的
    /// 条目并跑一次真实的 [`Engine::prune`]，确认客人侧宽限过滤会清空 roster。
    ///
    /// 只在 `ASTRAL_STEAM_DEBUG=1` 时由 Dart 侧按钮触发；结束后恢复原状态。
    fn debug_guest_roster_probe(&mut self) -> Result<String, String> {
        if !*STEAM_DEBUG {
            return Err("需要 ASTRAL_STEAM_DEBUG=1 才能运行诊断".to_string());
        }
        let saved_role = self.role;
        let saved_roster = std::mem::take(&mut self.roster);
        let saved_offline = std::mem::take(&mut self.guest_offline_since);

        let host_sid = 76561190000000002u64;
        let expired = Instant::now() - roster_policy::OFFLINE_GRACE - Duration::from_secs(1);
        self.role = Role::Guest;
        self.roster = vec![RosterEntry {
            peer_id: 1,
            steam_id: host_sid,
            nickname: "ghost-host".to_string(),
            vip: proto::HOST_VIP,
            online: false,
            is_host: true,
            latency_ms: 0,
            via_relay: false,
            bytes_in: 0,
            bytes_out: 0,
        }];
        let before = self.roster.len();
        self.guest_offline_since.insert(host_sid, expired);
        self.prune();
        let after = self.roster.len();
        let removed = self.roster.iter().all(|e| e.steam_id != host_sid);
        debug_log(
            "debug_guest_roster_probe",
            format!("before={before} after={after} removed={removed}"),
        );

        // 恢复真实状态，诊断不能污染正在进行的房间。
        self.role = saved_role;
        self.roster = saved_roster;
        self.guest_offline_since = saved_offline;

        if !removed || after != 0 {
            return Err(format!(
                "诊断失败：客人侧宽限过滤未清空 roster（{before} -> {after}）"
            ));
        }
        Ok(format!(
            "客人侧宽限过滤生效：房主离线超宽限期后 roster {before} -> {after}，已清空"
        ))
    }

    fn prune(&mut self) {
        let now = Instant::now();
        // 大厅操作超时：明确回执失败，别让 Dart 侧一直转圈。
        let lobby_expired = self
            .pending_lobby
            .as_ref()
            .map(|p| now >= p.deadline)
            .unwrap_or(false);
        if lobby_expired {
            if let Some(pending) = self.pending_lobby.take() {
                debug_log("lobby_timeout", "deadline reached");
                match pending.reply {
                    LobbyReply::One(tx) => {
                        let _ = tx.send(Err(
                            "Steam 大厅操作超时，请检查 Steam 是否在线后重试".to_string()
                        ));
                    }
                    LobbyReply::Many(tx) => {
                        let _ = tx.send(Err("搜索房间超时，请重试".to_string()));
                    }
                }
            }
        }
        self.flood_seen
            .retain(|_, at| now.duration_since(*at) < DEDUP_WINDOW);
        self.pending
            .retain(|_, p| now.duration_since(p.at) < Duration::from_secs(30));
        self.assign_cache
            .retain(|_, (_, _, at)| now.duration_since(*at) < Duration::from_secs(30));
        if self.role == Role::Host {
            let views: Vec<MemberView> = self
                .members
                .iter()
                .map(|(sid, m)| MemberView {
                    steam_id: *sid,
                    is_self: *sid == self.self_steam_id,
                    is_host: m.is_host,
                    online: m.online,
                    last_seen: m.last_seen,
                    offline_since: m.offline_since,
                })
                .collect();
            let mut removed = false;
            for sid in roster_policy::prune_plan(&views, now) {
                let was_online = self.members.get(&sid).map(|m| m.online).unwrap_or(false);
                if was_online {
                    // 在线心跳超时：先标离线并开启宽限期，给一次重连机会。
                    debug_log("prune_timeout", format!("sid={sid} stage=offline"));
                    self.remove_member(sid, "成员心跳超时");
                } else {
                    // 离线且超过宽限期：真正摘除，随后广播成员表。
                    debug_log(
                        "prune_remove",
                        format!("sid={sid} grace={:?}", roster_policy::OFFLINE_GRACE),
                    );
                    self.conns.remove(&sid);
                    self.members.remove(&sid);
                    removed = true;
                }
            }
            if removed {
                self.broadcast_roster();
            }
        } else if self.role == Role::Guest {
            // 客人侧本地兜底：房主可能因丢包没把离线成员摘掉，这里按同一宽限期
            // 过滤成员表，避免真·幽灵长期停留在客机列表里。
            let expired: Vec<u64> = self
                .guest_offline_since
                .iter()
                .filter(|(_, at)| now.duration_since(**at) >= roster_policy::OFFLINE_GRACE)
                .map(|(sid, _)| *sid)
                .collect();
            if !expired.is_empty() {
                for sid in &expired {
                    debug_log("guest_prune_offline", format!("sid={sid}"));
                    self.guest_offline_since.remove(sid);
                }
                self.roster.retain(|e| !expired.contains(&e.steam_id));
            }
            // 已不在成员表里的 id 不再需要计时器，避免 HashMap 无限增长。
            let present: HashSet<u64> = self.roster.iter().map(|e| e.steam_id).collect();
            self.guest_offline_since
                .retain(|sid, _| present.contains(sid));
        }
    }

    fn publish(&mut self, force: bool) {
        if !force && self.last_publish.elapsed() < Duration::from_secs(1) {
            return;
        }
        self.last_publish = Instant::now();
        let members = self.collect_members();
        debug_log(
            "publish",
            format!(
                "role={} total={} online={} roster={} active={}",
                match self.role {
                    Role::Idle => "idle",
                    Role::Host => "host",
                    Role::Guest => "guest",
                },
                self.members.len(),
                self.members.values().filter(|m| m.online).count(),
                self.roster.iter().filter(|e| e.online).count(),
                self.role != Role::Idle
            ),
        );
        let count = members.len() as u32;
        let host = self.role == Role::Host;
        let active = self.role != Role::Idle;
        let room = SteamRoomInfo {
            active,
            is_host: host,
            virtual_ip: if active {
                self.my_vip.to_string()
            } else {
                String::new()
            },
            network: if active {
                "100.100.100.0/24".to_string()
            } else {
                String::new()
            },
            member_count: count,
            self_peer_id: self.my_peer_id,
            members,
        };
        publish_room(room);
        let vip = self.my_vip.to_string();
        let message = self.message.clone();
        update_status(|s| {
            s.room_active = active;
            s.is_host = host;
            s.virtual_ip = if active { vip } else { String::new() };
            s.member_count = count;
            if !message.is_empty() {
                s.message = message;
            }
        });
    }

    fn collect_members(&self) -> Vec<SteamMemberInfo> {
        let mut out: Vec<SteamMemberInfo> = Vec::new();
        if self.role == Role::Host {
            let views: Vec<MemberView> = self
                .members
                .iter()
                .map(|(sid, m)| MemberView {
                    steam_id: *sid,
                    is_self: *sid == self.self_steam_id,
                    is_host: m.is_host,
                    online: m.online,
                    last_seen: m.last_seen,
                    offline_since: m.offline_since,
                })
                .collect();
            let visible: HashSet<u64> =
                roster_policy::visible_members(&views).into_iter().collect();
            for m in self.members.values() {
                if !visible.contains(&m.steam_id) {
                    continue;
                }
                // 只把在线成员交给 UI / 节点列表（本机除外），离线成员留在
                // 成员表里等宽限期到点后被 prune 摘除。
                if !m.online && m.steam_id != self.self_steam_id {
                    continue;
                }
                let (bytes_in, bytes_out) = if m.steam_id == self.self_steam_id {
                    (self.rx_bytes, self.tx_bytes)
                } else {
                    (m.bytes_in, m.bytes_out)
                };
                out.push(SteamMemberInfo {
                    peer_id: m.peer_id,
                    steam_id: m.steam_id.to_string(),
                    nickname: m.nickname.clone(),
                    virtual_ip: m.vip.to_string(),
                    latency_ms: m.latency_ms,
                    online: m.online,
                    is_host: m.is_host,
                    is_self: m.steam_id == self.self_steam_id,
                    via_relay: m.via_relay,
                    bytes_in,
                    bytes_out,
                });
            }
        } else {
            for e in &self.roster {
                let is_self = e.steam_id == self.self_steam_id;
                // 离线成员在宽限期内保留在成员表里等待重连，但不进 UI；
                // 超过宽限期的条目已在 `prune` 中本地过滤。
                if !e.online && !is_self {
                    continue;
                }
                out.push(SteamMemberInfo {
                    peer_id: e.peer_id,
                    steam_id: e.steam_id.to_string(),
                    nickname: e.nickname.clone(),
                    virtual_ip: e.vip.to_string(),
                    latency_ms: e.latency_ms,
                    online: e.online,
                    is_host: e.is_host,
                    is_self,
                    // 客人视角：到房主那条用本机连接；其它成员要经过房主转发，
                    // 因此任一段走中继，端到端就是中转。
                    via_relay: if is_self {
                        false
                    } else if e.is_host {
                        self.host_via_relay
                    } else {
                        self.host_via_relay || e.via_relay
                    },
                    bytes_in: if is_self { self.rx_bytes } else { e.bytes_in },
                    bytes_out: if is_self { self.tx_bytes } else { e.bytes_out },
                });
            }
            if out.is_empty() && self.role == Role::Guest && self.my_peer_id != 0 {
                out.push(SteamMemberInfo {
                    peer_id: self.my_peer_id,
                    steam_id: self.self_steam_id.to_string(),
                    nickname: self.nickname.clone(),
                    virtual_ip: self.my_vip.to_string(),
                    latency_ms: 0,
                    online: true,
                    is_host: false,
                    is_self: true,
                    via_relay: false,
                    bytes_in: self.rx_bytes,
                    bytes_out: self.tx_bytes,
                });
            }
        }
        out.sort_by_key(|m| m.peer_id);
        out
    }

    fn assign_member(&mut self, steam_id: u64) -> (u32, Ipv4Addr) {
        if let Some((peer_id, vip, at)) = self.assign_cache.get(&steam_id) {
            if at.elapsed() < Duration::from_secs(30) {
                let pair = (*peer_id, *vip);
                self.assign_cache
                    .insert(steam_id, (pair.0, pair.1, Instant::now()));
                return pair;
            }
        }
        let used_vips: HashSet<u8> = self
            .members
            .values()
            .filter(|m| m.online)
            .map(|m| m.vip.octets()[3])
            .collect();
        let mut octet = 2u8;
        while octet < 255 && used_vips.contains(&octet) {
            octet += 1;
        }
        let used_peers: HashSet<u32> = self.members.values().map(|m| m.peer_id).collect();
        let mut peer_id = 2u32;
        while used_peers.contains(&peer_id) {
            peer_id += 1;
        }
        let vip = proto::vip(octet);
        self.assign_cache
            .insert(steam_id, (peer_id, vip, Instant::now()));
        (peer_id, vip)
    }

    fn roster_entries(&self) -> Vec<RosterEntry> {
        let mut out: Vec<RosterEntry> = self
            .members
            .values()
            .map(|m| {
                // 房主自己的成员项不累计流量，用引擎级计数器。
                let (bytes_in, bytes_out) = if m.steam_id == self.self_steam_id {
                    (self.rx_bytes, self.tx_bytes)
                } else {
                    (m.bytes_in, m.bytes_out)
                };
                RosterEntry {
                    peer_id: m.peer_id,
                    steam_id: m.steam_id,
                    nickname: m.nickname.clone(),
                    vip: m.vip,
                    online: m.online,
                    is_host: m.is_host,
                    latency_ms: m.latency_ms,
                    via_relay: m.via_relay,
                    bytes_in,
                    bytes_out,
                }
            })
            .collect();
        out.sort_by_key(|e| e.peer_id);
        out
    }

    fn broadcast_roster(&mut self) {
        if self.role != Role::Host {
            return;
        }
        let body = proto::roster(&self.roster_entries());
        let bytes = proto::encode(
            proto::KIND_CONTROL,
            proto::FLAG_FLOOD,
            proto::HOST_VIP,
            proto::BROADCAST_VIP,
            &body,
        );
        self.send_to_all(&bytes, SendFlags::RELIABLE, None);
        self.last_roster_at = Instant::now();
    }

    fn vip_for_peer(&self, peer_id: u32) -> Option<Ipv4Addr> {
        if self.role == Role::Idle {
            return None;
        }
        if peer_id == self.my_peer_id && self.my_peer_id != 0 {
            return Some(self.my_vip);
        }
        if self.role == Role::Host {
            self.members
                .values()
                .find(|m| m.peer_id == peer_id && m.online)
                .map(|m| m.vip)
        } else {
            self.roster
                .iter()
                .find(|e| e.peer_id == peer_id)
                .map(|e| e.vip)
        }
    }

    fn peer_id_of_vip(&self, vip: Ipv4Addr) -> Option<u32> {
        if vip == self.my_vip && self.my_peer_id != 0 {
            return Some(self.my_peer_id);
        }
        if self.role == Role::Host {
            self.members
                .values()
                .find(|m| m.vip == vip)
                .map(|m| m.peer_id)
        } else {
            self.roster.iter().find(|e| e.vip == vip).map(|e| e.peer_id)
        }
    }

    fn steam_id_of_vip(&self, vip: Ipv4Addr) -> Option<u64> {
        if self.role == Role::Host {
            self.members
                .values()
                .find(|m| m.vip == vip && m.online)
                .map(|m| m.steam_id)
        } else {
            self.roster
                .iter()
                .find(|e| e.vip == vip)
                .map(|e| e.steam_id)
        }
    }

    fn seen_recently(&mut self, frame: &Frame<'_>) -> bool {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        frame.src.hash(&mut hasher);
        frame.kind.hash(&mut hasher);
        frame.payload.hash(&mut hasher);
        let key = hasher.finish();
        if let Some(at) = self.flood_seen.get(&key) {
            if at.elapsed() < DEDUP_WINDOW {
                return true;
            }
        }
        self.flood_seen.insert(key, Instant::now());
        false
    }
}

fn is_dead_state(state: NetworkingConnectionState) -> bool {
    matches!(
        state,
        NetworkingConnectionState::ClosedByPeer
            | NetworkingConnectionState::ProblemDetectedLocally
            | NetworkingConnectionState::None
    )
}

/// 读取大厅的全部 key/value（只取 `ag_*` 也用不上筛选，直接全量读回）。
fn read_lobby_pairs(mm: &Matchmaking, lobby: LobbyId) -> Vec<(String, String)> {
    let count = mm.lobby_data_count(lobby);
    let mut out = Vec::with_capacity(count as usize);
    for i in 0..count {
        if let Some(pair) = mm.lobby_data_by_index(lobby, i) {
            out.push(pair);
        }
    }
    out
}

fn lobby_info(snapshot: &LobbySnapshot) -> SteamLobbyInfo {
    SteamLobbyInfo {
        lobby_id: snapshot.lobby_id.to_string(),
        game_id: snapshot.game_id.clone(),
        name: snapshot.name.clone(),
        gate: snapshot.gate.as_str().to_string(),
        version: snapshot.version.clone(),
        host_steam_id: snapshot.host_steam_id.clone(),
        players: snapshot.players,
        capacity: snapshot.capacity,
        joinable: true,
    }
}

fn engine_thread(rx: Receiver<Cmd>) {
    // Steam 通过 `+connect_lobby <id>` 拉起应用时，命令行里才有邀请信息；
    // 在初始化前就记下来，Dart 订阅状态时能直接拿到。
    if let Some(lobby_id) = lobby::parse_connect_lobby_args(std::env::args()) {
        debug_log("invite_argv", format!("lobby={lobby_id}"));
        if let Ok(mut pending) = PENDING_INVITE.lock() {
            *pending = Some(lobby_id);
        }
    }
    let client = match Client::init_app(resolve_appid()) {
        Ok(c) => c,
        Err(e) => {
            set_status(SteamStatusInfo {
                message: format!("Steam 初始化失败（Steam 客户端是否在运行？）: {e:?}"),
                ..Default::default()
            });
            if let Ok(mut failed) = BOOT_FAILED_AT.lock() {
                *failed = Some(Instant::now());
            }
            if let Ok(mut guard) = TX.lock() {
                *guard = None;
            }
            return;
        }
    };

    let self_steam_id = client.user().steam_id().raw();
    let persona = client.friends().name();
    set_status(SteamStatusInfo {
        ok: true,
        logged_on: client.user().logged_on(),
        steam_id: self_steam_id.to_string(),
        persona: persona.clone(),
        relay_ready: false,
        message: "已连接 Steam，正在获取 SDR 中继网络…".to_string(),
        ..Default::default()
    });
    client.networking_utils().init_relay_network_access();

    let mut engine = Engine::new(client, self_steam_id, persona);
    loop {
        let timeout = engine.tick_interval();
        match rx.recv_timeout(timeout) {
            Ok(cmd) => engine.handle_cmd(cmd),
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
        engine.tick();
    }
    engine.shutdown_room("Steam 线程结束");
}
