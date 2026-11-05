//! Pear 组网引擎：单线程持有侧车链路、wintun 会话与房间状态。
//!
//! 拓扑与 Steam 模式一致：星型。房主的侧车接受成员连接，客人连房主的
//! HyperDHT 公钥；IP 包、控制帧与 RPC 都由房主转发。
//!
//! 侧车（Bare/Node + hyperdht）只做链路多路复用：每条成员连接一个 id，Rust 把
//! 该 id 当作成员键。房间成员表、虚拟 IP 分配、心跳与转发逻辑都在这里。

use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::Ipv4Addr;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine as _;
use lazy_static::lazy_static;
use serde_json::{json, Value};
use tokio::sync::oneshot;

use crate::api::p2p::{AppCallResultC, AppInboundEventC, AppInboundKindC};
use crate::api::pear::{PearMemberInfo, PearRoomInfo, PearStatusInfo};
use crate::frb_generated::StreamSink;
use crate::steam_tunnel::proto::{self, Frame, RosterEntry};
use crate::steam_tunnel::tun::{self, TunRoom};

/// 客人等待房主 Welcome 的上限（DHT 打洞 + 中继比 Steam 慢）。
const START_TIMEOUT: Duration = Duration::from_secs(30);
/// 心跳周期。
const HEARTBEAT: Duration = Duration::from_secs(3);
/// 广播去重窗口。
const DEDUP_WINDOW: Duration = Duration::from_secs(2);
/// 侧车断线后的重连间隔。
const RECONNECT_DELAY: Duration = Duration::from_secs(5);
/// 初始化失败后的重试间隔。
const BOOT_RETRY: Duration = Duration::from_secs(5);
/// 客机眼里通往房主的唯一链路 id。
const HOST_LINK_KEY: u64 = 1;
/// Pear 独立虚拟网卡，避免与 Steam 网卡复用。
const PEAR_ADAPTER: &str = "AstralPear";
const PEAR_ADAPTER_GUID: u128 = 0x8f3c_1d52_6a4b_4e77_ac91_2b34_7de5_0c68;

enum Cmd {
    Start {
        host: bool,
        host_key: String,
        join_token: String,
        nickname: String,
        reply: oneshot::Sender<Result<PearRoomInfo, String>>,
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
    static ref STATUS: Mutex<PearStatusInfo> = Mutex::new(PearStatusInfo::default());
    static ref ROOM: Mutex<PearRoomInfo> = Mutex::new(PearRoomInfo::default());
    static ref INBOUND: Mutex<Option<StreamSink<AppInboundEventC>>> = Mutex::new(None);
    static ref BOOT_FAILED_AT: Mutex<Option<Instant>> = Mutex::new(None);
}

fn set_status(status: PearStatusInfo) {
    if let Ok(mut s) = STATUS.lock() {
        *s = status;
    }
}

fn update_status(f: impl FnOnce(&mut PearStatusInfo)) {
    if let Ok(mut s) = STATUS.lock() {
        f(&mut s);
    }
}

fn publish_room(room: PearRoomInfo) {
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

/// 读取当前 Pear 状态；首次调用会拉起后台线程。
pub(crate) fn status() -> PearStatusInfo {
    let _ = ensure_boot();
    STATUS.lock().map(|s| s.clone()).unwrap_or_default()
}

pub(crate) fn room_info() -> PearRoomInfo {
    ROOM.lock().map(|r| r.clone()).unwrap_or_default()
}

pub(crate) fn subscribe_app_inbound(sink: StreamSink<AppInboundEventC>) {
    if let Ok(mut guard) = INBOUND.lock() {
        *guard = Some(sink);
    }
}

pub(crate) fn my_peer_id() -> u32 {
    ROOM.lock().map(|r| r.self_peer_id).unwrap_or(0)
}

/// 侧车目录：优先环境变量，其次 exe 同目录 / data 目录，最后向仓库上级查找
/// （Debug 运行时 exe 在 build/ 下）。
fn resolve_pear_dir() -> Option<PathBuf> {
    const SCRIPT: &str = "pear_tunnel.mjs";
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(v) = std::env::var("ASTRAL_PEAR_DIR") {
        let v = v.trim();
        if !v.is_empty() {
            candidates.push(PathBuf::from(v));
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            candidates.push(dir.join("pear"));
            candidates.push(dir.join("data").join("pear"));
            let mut cur = Some(dir);
            for _ in 0..8 {
                let Some(d) = cur else { break };
                candidates.push(d.join("pear"));
                cur = d.parent();
            }
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        candidates.push(cwd.join("pear"));
        candidates.push(cwd);
    }
    candidates.into_iter().find(|p| p.join(SCRIPT).is_file())
}

/// Pear 运行时：优先内置的 Holepunch Bare，其次开发机 / 兜底的 Node。
struct PearRuntime {
    exe: PathBuf,
    bare: bool,
}

fn resolve_runtime(pear_dir: &Path) -> PearRuntime {
    if let Ok(v) = std::env::var("ASTRAL_PEAR_BARE") {
        let p = PathBuf::from(v.trim());
        if p.is_file() {
            return PearRuntime {
                exe: p,
                bare: true,
            };
        }
    }
    let mut bare_candidates = vec![
        // `pear/` 目录随构建产物复制到 data/pear，Bare 运行时也一起分发。
        pear_dir
            .join("node_modules")
            .join("bare-runtime-win32-x64")
            .join("bin")
            .join("bare.exe"),
    ];
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            bare_candidates.push(dir.join("pear-runtime").join("bare.exe"));
            bare_candidates.push(dir.join("data").join("pear-runtime").join("bare.exe"));
            bare_candidates.push(dir.join("bare.exe"));
        }
    }
    for cand in bare_candidates {
        if cand.is_file() {
            return PearRuntime {
                exe: cand,
                bare: true,
            };
        }
    }
    PearRuntime {
        exe: resolve_node(),
        bare: false,
    }
}

fn resolve_node() -> PathBuf {
    if let Ok(v) = std::env::var("ASTRAL_PEAR_NODE") {
        let p = PathBuf::from(v.trim());
        if p.is_file() {
            return p;
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            for cand in [
                dir.join("node").join("node.exe"),
                dir.join("data").join("node").join("node.exe"),
                dir.join("node.exe"),
            ] {
                if cand.is_file() {
                    return cand;
                }
            }
        }
    }
    PathBuf::from("node")
}

fn random_key() -> u64 {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(1);
    (nanos.rotate_left(17) | 1).max(2)
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
    let Some(dir) = resolve_pear_dir() else {
        set_status(PearStatusInfo {
            ok: false,
            message: "未找到 Pear 运行时：请把 pear/ 目录（含 pear_tunnel.mjs、node_modules \
                     与内置 Bare）放到程序目录，或设置 ASTRAL_PEAR_DIR"
                .to_string(),
            ..Default::default()
        });
        if let Ok(mut failed) = BOOT_FAILED_AT.lock() {
            *failed = Some(Instant::now());
        }
        return None;
    };
    let (tx, rx) = mpsc::channel::<Cmd>();
    thread::Builder::new()
        .name("astral-pear".to_string())
        .spawn(move || engine_thread(rx, dir))
        .ok()?;
    *guard = Some(tx.clone());
    Some(tx)
}

fn boot_error() -> String {
    STATUS
        .lock()
        .map(|s| s.message.clone())
        .unwrap_or_else(|_| "Pear 线程未启动".to_string())
}

fn tx_handle() -> Result<Sender<Cmd>, String> {
    ensure_boot().ok_or_else(boot_error)
}

pub(crate) async fn start(
    host: bool,
    host_key: String,
    join_token: String,
    nickname: String,
) -> Result<PearStatusInfo, String> {
    let tx = tx_handle()?;
    let (reply_tx, reply_rx) = oneshot::channel();
    tx.send(Cmd::Start {
        host,
        host_key,
        join_token,
        nickname,
        reply: reply_tx,
    })
    .map_err(|e| format!("Pear 线程不可用: {e}"))?;
    match tokio::time::timeout(START_TIMEOUT, reply_rx).await {
        Ok(Ok(Ok(_))) => Ok(status()),
        Ok(Ok(Err(e))) => Err(e),
        Ok(Err(_)) => Err("Pear 线程已退出".to_string()),
        Err(_) => {
            let _ = tx.send(Cmd::Stop);
            Err("Pear 组网启动超时（30 秒内未能建立连接）".to_string())
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
    .map_err(|e| format!("Pear 线程不可用: {e}"))?;
    let wait = Duration::from_millis(if timeout_ms <= 0 {
        5000
    } else {
        timeout_ms as u64
    });
    match tokio::time::timeout(wait, reply_rx).await {
        Ok(Ok(Ok(v))) => Ok(v),
        Ok(Ok(Err(e))) => Err(e),
        Ok(Err(_)) => Err("Pear RPC 已取消".to_string()),
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
    .map_err(|e| format!("Pear 线程不可用: {e}"))?;
    match tokio::time::timeout(Duration::from_secs(3), reply_rx).await {
        Ok(Ok(v)) => v,
        Ok(Err(_)) => Err("Pear RPC 已取消".to_string()),
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
    .map_err(|e| format!("Pear 线程不可用: {e}"))?;
    match tokio::time::timeout(Duration::from_secs(3), reply_rx).await {
        Ok(Ok(v)) => Ok(v),
        Ok(Err(_)) => Err("Pear 线程已退出".to_string()),
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
    .map_err(|e| format!("Pear 线程不可用: {e}"))?;
    let wait = Duration::from_millis(if timeout_ms <= 0 {
        5000
    } else {
        timeout_ms as u64
    });
    match tokio::time::timeout(wait, reply_rx).await {
        Ok(Ok(Ok(ms))) => Ok(ms as i64),
        Ok(Ok(Err(e))) => Err(e),
        Ok(Err(_)) => Err("Pear RPC 已取消".to_string()),
        Err(_) => Err("Request timeout".to_string()),
    }
}

// ---------------------------------------------------------------------------
// 侧车链路
// ---------------------------------------------------------------------------

enum LinkEvent {
    Ready { self_key: String },
    PeerOpen(u64),
    PeerClose(u64),
    Data(u64, Vec<u8>),
    Error(String),
    Exited,
}

struct PearLink {
    child: Child,
    stdin: Option<ChildStdin>,
    events: Receiver<LinkEvent>,
    ready: bool,
    self_key: String,
    peer_ids: HashSet<u64>,
}

impl PearLink {
    fn spawn(dir: &Path, host: bool, host_key: &str) -> Result<Self, String> {
        let script = dir.join("pear_tunnel.mjs");
        if !script.is_file() {
            return Err(format!("未找到 Pear 侧车脚本: {}", script.display()));
        }
        let runtime = resolve_runtime(dir);
        let mut cmd = Command::new(&runtime.exe);
        cmd.arg(&script)
            .current_dir(dir)
            // 用环境变量传启动参数：Bare 的 stdin 在监听器就绪前可能丢数据，
            // 环境变量没有这个竞态。
            .env("PEAR_ROLE", if host { "host" } else { "guest" })
            .env("PEAR_HOST_KEY", host_key)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        #[cfg(target_os = "windows")]
        {
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(0x0800_0000);
        }
        let mut child = cmd.spawn().map_err(|e| {
            let kind = if runtime.bare { "内置 Bare" } else { "Node" };
            format!("启动 Pear 运行时失败（{kind}）: {e}")
        })?;
        let stdout = child.stdout.take().ok_or("无法读取 Pear 运行时输出")?;
        let stderr = child.stderr.take();
        let stdin = child.stdin.take();
        let (tx, rx) = mpsc::channel::<LinkEvent>();
        thread::Builder::new()
            .name("astral-pear-io".to_string())
            .spawn(move || read_events(stdout, tx))
            .map_err(|e| format!("启动 Pear 链路线程失败: {e}"))?;
        if let Some(stderr) = stderr {
            let _ = thread::Builder::new()
                .name("astral-pear-err".to_string())
                .spawn(move || {
                    let reader = BufReader::new(stderr);
                    for _ in reader.lines() {}
                });
        }
        let link = Self {
            child,
            stdin,
            events: rx,
            ready: false,
            self_key: String::new(),
            peer_ids: HashSet::new(),
        };
        Ok(link)
    }

    fn write_json(&mut self, value: &Value) -> bool {
        let Some(stdin) = self.stdin.as_mut() else {
            return false;
        };
        let line = format!("{value}\n");
        stdin.write_all(line.as_bytes()).is_ok() && stdin.flush().is_ok()
    }

    fn send(&mut self, to: u64, bytes: &[u8]) -> bool {
        let data = B64.encode(bytes);
        self.write_json(&json!({"op": "send", "to": to, "data": data}))
    }

    fn flood(&mut self, bytes: &[u8], except: Option<u64>) -> bool {
        let data = B64.encode(bytes);
        self.write_json(&json!({
            "op": "send",
            "flood": true,
            "except": except,
            "data": data,
        }))
    }

    fn shutdown(&mut self) {
        let _ = self.write_json(&json!({"op": "stop"}));
        let _ = self.child.kill();
        let _ = self.child.wait();
        self.stdin = None;
    }
}

fn read_events<R: Read>(stdout: R, tx: Sender<LinkEvent>) {
    let reader = BufReader::new(stdout);
    for line in reader.lines() {
        let Ok(line) = line else { break };
        let Ok(value) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        match value.get("op").and_then(|v| v.as_str()) {
            Some("ready") => {
                let self_key = value
                    .get("selfKey")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let _ = tx.send(LinkEvent::Ready { self_key });
            }
            Some("peer") => {
                let id = value.get("id").and_then(|v| v.as_u64()).unwrap_or(0);
                let open = value.get("state").and_then(|v| v.as_str()) == Some("open");
                let _ = tx.send(if open {
                    LinkEvent::PeerOpen(id)
                } else {
                    LinkEvent::PeerClose(id)
                });
            }
            Some("data") => {
                let from = value.get("from").and_then(|v| v.as_u64());
                let data = value.get("data").and_then(|v| v.as_str());
                if let (Some(from), Some(data)) = (from, data) {
                    if let Ok(bytes) = B64.decode(data) {
                        let _ = tx.send(LinkEvent::Data(from, bytes));
                    }
                }
            }
            Some("error") => {
                let message = value
                    .get("message")
                    .and_then(|v| v.as_str())
                    .unwrap_or("Pear 侧车错误")
                    .to_string();
                let _ = tx.send(LinkEvent::Error(message));
            }
            _ => {}
        }
    }
    let _ = tx.send(LinkEvent::Exited);
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
    /// 侧车链路 id（房主用于转发）。
    key: u64,
    /// 成员自报 id（用于成员表识别自己）。
    sid: u64,
    nickname: String,
    vip: Ipv4Addr,
    online: bool,
    is_host: bool,
    latency_ms: u32,
    bytes_in: u64,
    bytes_out: u64,
    last_seen: Instant,
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
    pear_dir: PathBuf,
    role: Role,
    join_token: String,
    nickname: String,
    self_key: u64,

    link: Option<PearLink>,
    guest_open: bool,
    host_key: String,

    tun: Option<TunRoom>,
    my_vip: Ipv4Addr,
    my_peer_id: u32,

    members: HashMap<u64, Member>,
    assign_cache: HashMap<u64, (u32, Ipv4Addr, Instant)>,
    roster: Vec<RosterEntry>,

    batch_up: HashMap<Ipv4Addr, Vec<u8>>,
    batch_flood: Vec<u8>,

    pending: HashMap<u64, PendingEntry>,
    inbound_replies: HashMap<u64, (Ipv4Addr, u64)>,
    next_token: u64,
    next_request: u64,

    flood_seen: HashMap<u64, Instant>,

    hello_sent: bool,
    reconnect_at: Option<Instant>,
    start_reply: Option<oneshot::Sender<Result<PearRoomInfo, String>>>,
    start_deadline: Option<Instant>,

    last_heartbeat: Instant,
    last_roster_at: Instant,
    last_publish: Instant,

    /// 房主发出 PING 的时刻（按成员链路 id）；收到 PONG 后换算 RTT。
    ping_sent_at: HashMap<u64, Instant>,
    /// 客机发出通往房主 PING 的时刻。
    guest_ping_at: Option<Instant>,
    /// 客机实测的本机↔房主 RTT；房主下发的 Roster 里该字段恒为 0，
    /// 收到 Roster 后要用这个值回填房主条目，避免延迟显示被刷回 0ms。
    guest_host_latency_ms: u32,

    rx_bytes: u64,
    tx_bytes: u64,
    drops: u64,
    message: String,
}

impl Engine {
    fn new(pear_dir: PathBuf) -> Self {
        Self {
            pear_dir,
            role: Role::Idle,
            join_token: String::new(),
            nickname: String::new(),
            self_key: 0,
            link: None,
            guest_open: false,
            host_key: String::new(),
            tun: None,
            my_vip: Ipv4Addr::UNSPECIFIED,
            my_peer_id: 0,
            members: HashMap::new(),
            assign_cache: HashMap::new(),
            roster: Vec::new(),
            batch_up: HashMap::new(),
            batch_flood: Vec::new(),
            pending: HashMap::new(),
            inbound_replies: HashMap::new(),
            next_token: 0,
            next_request: 0,
            flood_seen: HashMap::new(),
            hello_sent: false,
            reconnect_at: None,
            start_reply: None,
            start_deadline: None,
            last_heartbeat: Instant::now(),
            last_roster_at: Instant::now() - Duration::from_secs(10),
            last_publish: Instant::now() - Duration::from_secs(10),
            ping_sent_at: HashMap::new(),
            guest_ping_at: None,
            guest_host_latency_ms: 0,
            rx_bytes: 0,
            tx_bytes: 0,
            drops: 0,
            message: String::new(),
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
                host_key,
                join_token,
                nickname,
                reply,
            } => self.start_room(host, host_key, join_token, nickname, reply),
            Cmd::Stop => self.shutdown_room("Pear 组网已停止"),
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

    fn start_room(
        &mut self,
        host: bool,
        host_key: String,
        join_token: String,
        nickname: String,
        reply: oneshot::Sender<Result<PearRoomInfo, String>>,
    ) {
        self.shutdown_room("重新开始 Pear 组网");
        self.nickname = if nickname.trim().is_empty() {
            "Pear 用户".to_string()
        } else {
            nickname.trim().to_string()
        };
        self.join_token = join_token;
        self.rx_bytes = 0;
        self.tx_bytes = 0;
        self.drops = 0;
        self.host_key = host_key.trim().to_lowercase();

        if host {
            self.role = Role::Host;
            self.self_key = 0;
            self.my_vip = proto::HOST_VIP;
            self.my_peer_id = 1;
            let tun = match tun::open_named(
                proto::HOST_VIP,
                proto::MTU,
                PEAR_ADAPTER,
                PEAR_ADAPTER_GUID,
                "Astral Pear",
            ) {
                Ok(t) => t,
                Err(e) => {
                    self.role = Role::Idle;
                    let _ = reply.send(Err(e.clone()));
                    self.message = e;
                    return;
                }
            };
            self.tun = Some(tun);
            match PearLink::spawn(&self.pear_dir, true, "") {
                Ok(link) => self.link = Some(link),
                Err(e) => {
                    self.shutdown_room("Pear 运行时启动失败");
                    let _ = reply.send(Err(e.clone()));
                    self.message = e;
                    return;
                }
            }
            self.start_reply = Some(reply);
            self.message = "正在启动 Pear 网络（HyperDHT）…".to_string();
            self.publish(true);
            return;
        }

        // 客人：先连房主，拿到 Welcome 再建网卡（需要分配到的虚拟 IP）。
        if self.host_key.len() != 64 || !self.host_key.chars().all(|c| c.is_ascii_hexdigit()) {
            let msg = "邀请缺少有效的 Pear 房主公钥，请让房主重新分享。".to_string();
            self.role = Role::Idle;
            let _ = reply.send(Err(msg.clone()));
            self.message = msg;
            return;
        }
        self.role = Role::Guest;
        self.self_key = random_key();
        self.guest_open = false;
        self.hello_sent = false;
        match PearLink::spawn(&self.pear_dir, false, &self.host_key) {
            Ok(link) => self.link = Some(link),
            Err(e) => {
                self.role = Role::Idle;
                let _ = reply.send(Err(e.clone()));
                self.message = e;
                return;
            }
        }
        self.start_reply = Some(reply);
        self.start_deadline = Some(Instant::now() + START_TIMEOUT);
        // 首次连接不要立刻进入"重连"分支：DHT 打洞/中继可能需要数秒，
        // 过早重启侧车会把正在建立的连接反复掐断，导致一直连不上房主。
        self.reconnect_at = None;
        self.message = "正在通过 Pear 网络连接房主…".to_string();
        self.publish(true);
    }

    fn shutdown_room(&mut self, reason: &str) {
        if let Some(tun) = self.tun.take() {
            tun.shutdown();
        }
        if let Some(mut link) = self.link.take() {
            link.shutdown();
        }
        self.guest_open = false;
        self.hello_sent = false;
        self.members.clear();
        self.roster.clear();
        self.pending.clear();
        self.inbound_replies.clear();
        self.batch_up.clear();
        self.batch_flood.clear();
        self.my_vip = Ipv4Addr::UNSPECIFIED;
        self.my_peer_id = 0;
        self.reconnect_at = None;
        self.start_deadline = None;
        self.role = Role::Idle;
        if let Some(tx) = self.start_reply.take() {
            let _ = tx.send(Err(reason.to_string()));
        }
        self.message = reason.to_string();
        update_status(|s| {
            s.ready = false;
            s.room_active = false;
            s.is_host = false;
            s.virtual_ip.clear();
            s.member_count = 0;
            s.message = reason.to_string();
        });
        publish_room(PearRoomInfo::default());
    }

    fn tick(&mut self) {
        self.poll_link();
        self.poll_tun();
        self.flush_out_batches();
        self.heartbeat();
        self.check_deadlines();
        self.prune();
        self.publish(false);
    }

    fn poll_link(&mut self) {
        let mut events: Vec<LinkEvent> = Vec::new();
        let mut exited: Option<String> = None;
        if let Some(link) = self.link.as_mut() {
            loop {
                match link.events.try_recv() {
                    Ok(ev) => events.push(ev),
                    Err(TryRecvError::Empty) => break,
                    Err(TryRecvError::Disconnected) => {
                        exited = Some("Pear 侧车连接已断开".to_string());
                        break;
                    }
                }
            }
            if exited.is_none() {
                if let Ok(Some(status)) = link.child.try_wait() {
                    exited = Some(format!("Pear 侧车已退出（{status}）"));
                }
            }
        }
        for ev in events {
            self.on_link_event(ev);
        }
        if let Some(reason) = exited {
            if self.role != Role::Idle {
                self.shutdown_room(&reason);
            }
        }
    }

    fn on_link_event(&mut self, ev: LinkEvent) {
        match ev {
            LinkEvent::Ready { self_key } => {
                if let Some(link) = self.link.as_mut() {
                    link.ready = true;
                    link.self_key = self_key.clone();
                }
                if self.role == Role::Host {
                    if !self_key.is_empty() {
                        self.host_key = self_key;
                    }
                    if !self.members.contains_key(&0) {
                        self.members.insert(
                            0,
                            Member {
                                peer_id: 1,
                                key: 0,
                                sid: 0,
                                nickname: self.nickname.clone(),
                                vip: proto::HOST_VIP,
                                online: true,
                                is_host: true,
                                latency_ms: 0,
                                bytes_in: 0,
                                bytes_out: 0,
                                last_seen: Instant::now(),
                            },
                        );
                    }
                    self.message = "Pear 房间已开启，等待成员加入".to_string();
                    // 必须先发布状态再回包：start() 收到回包后会立刻读取 status()
                    // 取 host_key，晚发布会让 Dart 侧拿到空公钥导致建房失败。
                    self.publish(true);
                    if let Some(tx) = self.start_reply.take() {
                        let _ = tx.send(Ok(room_info()));
                    }
                } else {
                    // Ready 表示客机链路已建立（侧车在 socket open 后才发 ready），
                    // 这里兜底置真：即使旧版侧车漏发 peer open，握手也能开始。
                    self.guest_open = true;
                    self.message = "已接入 Pear 网络，正在连接房主…".to_string();
                    self.publish(true);
                }
            }
            LinkEvent::PeerOpen(id) => {
                if let Some(link) = self.link.as_mut() {
                    link.peer_ids.insert(id);
                }
                if self.role == Role::Guest && id == HOST_LINK_KEY {
                    self.guest_open = true;
                    self.message = "已连接 Pear 房主，正在握手…".to_string();
                } else if self.role == Role::Host {
                    self.message = "新的 Pear 连接已接入".to_string();
                }
            }
            LinkEvent::PeerClose(id) => {
                if let Some(link) = self.link.as_mut() {
                    link.peer_ids.remove(&id);
                }
                if self.role == Role::Guest {
                    self.guest_open = false;
                    self.hello_sent = false;
                    self.message = "与 Pear 房主的连接已断开，正在重连…".to_string();
                    // 房主链路断开后 Roster 已失效：清空成员表并立即发布，
                    // 避免 UI 继续显示过期成员，也让 Dart 侧能判定房主离线。
                    self.roster.clear();
                    self.guest_ping_at = None;
                    self.guest_host_latency_ms = 0;
                    self.publish(true);
                    self.reconnect_at = Some(Instant::now() + RECONNECT_DELAY);
                } else if self.role == Role::Host {
                    self.remove_member(id, "成员已断开");
                }
            }
            LinkEvent::Data(id, data) => {
                if let Some(m) = self.members.get_mut(&id) {
                    m.bytes_in += data.len() as u64;
                    m.last_seen = Instant::now();
                }
                self.rx_bytes += data.len() as u64;
                self.handle_message(id, &data);
            }
            LinkEvent::Error(msg) => {
                self.message = msg;
                if self.role == Role::Guest {
                    // DHT 打洞失败等链路错误是可重试的：不立刻判死，
                    // 交给重连逻辑重试，由启动截止时间兜底提示超时。
                    self.guest_open = false;
                    self.hello_sent = false;
                    if self.reconnect_at.is_none() {
                        self.reconnect_at = Some(Instant::now() + RECONNECT_DELAY);
                    }
                } else if self.start_reply.is_some() && self.role != Role::Idle {
                    let reason = self.message.clone();
                    self.shutdown_room(&reason);
                }
            }
            LinkEvent::Exited => {
                if self.role != Role::Idle {
                    self.shutdown_room("Pear 侧车已退出");
                }
            }
        }
    }

    fn remove_member(&mut self, key: u64, reason: &str) {
        if key == 0 {
            return;
        }
        if let Some(m) = self.members.get_mut(&key) {
            m.online = false;
            m.last_seen = Instant::now();
        }
        self.message = reason.to_string();
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
                self.send_to_host(&bytes);
            }
            Role::Host => {
                if flags & proto::FLAG_FLOOD != 0 {
                    self.send_to_all(&bytes, None);
                } else if let Some(key) = self.key_of_vip(dst) {
                    self.send_to_key(key, &bytes);
                } else {
                    self.drops += 1;
                }
            }
            Role::Idle => {}
        }
    }

    fn send_to_host(&mut self, bytes: &[u8]) -> bool {
        if !self.guest_open {
            return false;
        }
        let Some(link) = self.link.as_mut() else {
            return false;
        };
        if link.send(HOST_LINK_KEY, bytes) {
            self.tx_bytes += bytes.len() as u64;
            true
        } else {
            false
        }
    }

    fn send_to_key(&mut self, key: u64, bytes: &[u8]) -> bool {
        if key == 0 {
            return false;
        }
        let Some(link) = self.link.as_mut() else {
            return false;
        };
        if link.send(key, bytes) {
            self.tx_bytes += bytes.len() as u64;
            if let Some(m) = self.members.get_mut(&key) {
                m.bytes_out += bytes.len() as u64;
            }
            true
        } else {
            false
        }
    }

    fn send_to_all(&mut self, bytes: &[u8], exclude: Option<u64>) {
        let Some(link) = self.link.as_mut() else {
            return;
        };
        if link.flood(bytes, exclude) {
            self.tx_bytes += bytes.len() as u64;
        }
    }

    fn handle_message(&mut self, from_key: u64, data: &[u8]) {
        let Some(frame) = proto::decode(data) else {
            return;
        };
        match frame.kind {
            proto::KIND_IP => self.on_ip(from_key, &frame),
            proto::KIND_CONTROL => self.on_control(from_key, &frame),
            proto::KIND_RPC => self.on_rpc(from_key, &frame),
            _ => {}
        }
    }

    fn on_ip(&mut self, from_key: u64, frame: &Frame<'_>) {
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
                    self.send_to_all(&bytes, Some(from_key));
                } else if frame.dst == proto::HOST_VIP {
                    if let Some(tun) = self.tun.as_ref() {
                        for packet in proto::split_ipv4(frame.payload) {
                            let _ = tun.inject(packet);
                        }
                    }
                } else if let Some(key) = self.key_of_vip(frame.dst) {
                    let bytes = proto::encode(
                        proto::KIND_IP,
                        frame.flags,
                        frame.src,
                        frame.dst,
                        frame.payload,
                    );
                    self.send_to_key(key, &bytes);
                } else {
                    self.drops += 1;
                }
            }
            Role::Idle => {}
        }
    }

    fn on_control(&mut self, from_key: u64, frame: &Frame<'_>) {
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
                if hello.token != self.join_token {
                    let body = proto::kick("房间密码不匹配");
                    let bytes = proto::encode(
                        proto::KIND_CONTROL,
                        0,
                        proto::HOST_VIP,
                        proto::BROADCAST_VIP,
                        &body,
                    );
                    self.send_to_key(from_key, &bytes);
                    self.remove_member(from_key, "成员鉴权失败");
                    return;
                }
                let (peer_id, vip) = self.assign_member(from_key);
                self.members.insert(
                    from_key,
                    Member {
                        peer_id,
                        key: from_key,
                        sid: hello.steam_id,
                        nickname: if hello.nickname.trim().is_empty() {
                            format!("Pear 用户 {}", from_key)
                        } else {
                            hello.nickname
                        },
                        vip,
                        online: true,
                        is_host: false,
                        latency_ms: 0,
                        bytes_in: 0,
                        bytes_out: 0,
                        last_seen: Instant::now(),
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
                let bytes =
                    proto::encode(proto::KIND_CONTROL, 0, proto::HOST_VIP, vip, &body);
                self.send_to_key(from_key, &bytes);
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
                    match tun::open_named(
                        welcome.vip,
                        proto::MTU,
                        PEAR_ADAPTER,
                        PEAR_ADAPTER_GUID,
                        "Astral Pear",
                    ) {
                        Ok(t) => self.tun = Some(t),
                        Err(e) => {
                            let msg = format!("创建虚拟网卡失败: {e}");
                            self.shutdown_room(&msg);
                            return;
                        }
                    }
                }
                self.message = format!("已加入 Pear 房间，本机虚拟 IP {}", welcome.vip);
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
                self.send_frame_to_vip(frame.src, &bytes);
            }
            proto::CTL_PONG => {
                let now = Instant::now();
                if let Some(m) = self.members.get_mut(&from_key) {
                    m.last_seen = now;
                }
                if self.role == Role::Host {
                    if let Some(sent_at) = self.ping_sent_at.remove(&from_key) {
                        let ms = now
                            .duration_since(sent_at)
                            .as_millis()
                            .min(u32::MAX as u128) as u32;
                        if let Some(m) = self.members.get_mut(&from_key) {
                            m.latency_ms = ms;
                        }
                    }
                } else if self.role == Role::Guest && from_key == HOST_LINK_KEY {
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
                    self.shutdown_room(&reason);
                }
            }
            proto::CTL_BYE => {
                if self.role == Role::Guest {
                    let reason = proto::kick_reason(frame.payload);
                    self.shutdown_room(if reason.is_empty() {
                        "房主已关闭房间"
                    } else {
                        &reason
                    });
                } else {
                    self.remove_member(from_key, "成员已离开");
                }
            }
            _ => {}
        }
    }

    fn on_rpc(&mut self, _from_key: u64, frame: &Frame<'_>) {
        if self.role == Role::Host && frame.dst != proto::HOST_VIP {
            if let Some(key) = self.key_of_vip(frame.dst) {
                let bytes = proto::encode(
                    proto::KIND_RPC,
                    0,
                    frame.src,
                    frame.dst,
                    frame.payload,
                );
                self.send_to_key(key, &bytes);
            }
            return;
        }
        self.handle_rpc_local(frame);
    }

    fn handle_rpc_local(&mut self, frame: &Frame<'_>) {
        if let Some((op, call)) = proto::parse_rpc_call(frame.payload) {
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
        self.send_frame_to_vip(dst_vip, &bytes)
    }

    fn send_frame_to_vip(&mut self, dst_vip: Ipv4Addr, bytes: &[u8]) -> bool {
        match self.role {
            Role::Guest => self.send_to_host(bytes),
            Role::Host => {
                if dst_vip == proto::HOST_VIP {
                    false
                } else if let Some(key) = self.key_of_vip(dst_vip) {
                    self.send_to_key(key, bytes)
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
        self.maybe_reconnect();
        if self.role == Role::Guest && !self.guest_open {
            return;
        }
        if self.role == Role::Guest && !self.hello_sent {
            let body = proto::hello(&proto::HelloMsg {
                token: self.join_token.clone(),
                steam_id: self.self_key,
                nickname: self.nickname.clone(),
                version: proto::VERSION.to_string(),
            });
            let bytes = proto::encode(
                proto::KIND_CONTROL,
                0,
                Ipv4Addr::UNSPECIFIED,
                proto::HOST_VIP,
                &body,
            );
            if self.send_to_host(&bytes) {
                self.hello_sent = true;
            }
        }

        if self.last_heartbeat.elapsed() < HEARTBEAT {
            return;
        }
        self.last_heartbeat = Instant::now();
        let body = proto::simple_control(proto::CTL_PING);
        match self.role {
            Role::Host => {
                let keys: Vec<u64> = self
                    .members
                    .values()
                    .filter(|m| m.key != 0 && m.online)
                    .map(|m| m.key)
                    .collect();
                let sent_at = Instant::now();
                for key in keys {
                    self.ping_sent_at.insert(key, sent_at);
                }
                let bytes = proto::encode(
                    proto::KIND_CONTROL,
                    0,
                    proto::HOST_VIP,
                    proto::BROADCAST_VIP,
                    &body,
                );
                self.send_to_all(&bytes, None);
            }
            Role::Guest => {
                self.guest_ping_at = Some(Instant::now());
                let bytes = proto::encode(
                    proto::KIND_CONTROL,
                    0,
                    self.my_vip,
                    proto::HOST_VIP,
                    &body,
                );
                self.send_to_host(&bytes);
            }
            Role::Idle => {}
        }

        if self.role == Role::Host && self.last_roster_at.elapsed() > Duration::from_secs(5) {
            self.broadcast_roster();
        }
    }

    /// 房主链路断开后重启侧车重连（HyperDHT 不保证会话保持）。
    fn maybe_reconnect(&mut self) {
        if self.role != Role::Guest || self.guest_open {
            return;
        }
        if !self
            .reconnect_at
            .map(|at| Instant::now() >= at)
            .unwrap_or(false)
        {
            return;
        }
        self.reconnect_at = Some(Instant::now() + RECONNECT_DELAY);
        if let Some(mut old) = self.link.take() {
            old.shutdown();
        }
        match PearLink::spawn(&self.pear_dir, false, &self.host_key) {
            Ok(link) => {
                self.link = Some(link);
                self.hello_sent = false;
                self.message = "正在重新连接 Pear 房主…".to_string();
            }
            Err(e) => {
                self.message = e;
            }
        }
    }

    fn check_deadlines(&mut self) {
        if self.role != Role::Guest {
            return;
        }
        if let Some(deadline) = self.start_deadline {
            if Instant::now() >= deadline {
                let msg = "连接 Pear 房主超时：请确认对方已开启房间，且 HyperDHT 网络可用"
                    .to_string();
                self.shutdown_room(&msg);
            }
        }
    }

    fn prune(&mut self) {
        let now = Instant::now();
        self.flood_seen
            .retain(|_, at| now.duration_since(*at) < DEDUP_WINDOW);
        self.pending
            .retain(|_, p| now.duration_since(p.at) < Duration::from_secs(30));
        self.assign_cache
            .retain(|_, (_, _, at)| now.duration_since(*at) < Duration::from_secs(30));
        if self.role == Role::Host {
            let stale: Vec<u64> = self
                .members
                .iter()
                .filter(|(key, m)| {
                    **key != 0 && m.online && now.duration_since(m.last_seen) > Duration::from_secs(30)
                })
                .map(|(key, _)| *key)
                .collect();
            for key in stale {
                self.remove_member(key, "成员心跳超时");
            }
        }
    }

    fn publish(&mut self, force: bool) {
        if !force && self.last_publish.elapsed() < Duration::from_secs(1) {
            return;
        }
        self.last_publish = Instant::now();
        let members = self.collect_members();
        let count = members.len() as u32;
        let host = self.role == Role::Host;
        let active = self.role != Role::Idle;
        let ready = self.link.as_ref().map(|l| l.ready).unwrap_or(false);
        let room = PearRoomInfo {
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
        let host_key = self.host_key.clone();
        let nickname = self.nickname.clone();
        update_status(|s| {
            s.ok = true;
            s.ready = ready;
            s.room_active = active;
            s.is_host = host;
            s.virtual_ip = if active { vip } else { String::new() };
            s.member_count = count;
            s.host_key = host_key;
            s.nickname = nickname;
            if !message.is_empty() {
                s.message = message;
            }
        });
    }

    fn collect_members(&self) -> Vec<PearMemberInfo> {
        let mut out: Vec<PearMemberInfo> = Vec::new();
        if self.role == Role::Host {
            for m in self.members.values() {
                let (bytes_in, bytes_out) = if m.key == 0 {
                    (self.rx_bytes, self.tx_bytes)
                } else {
                    (m.bytes_in, m.bytes_out)
                };
                out.push(PearMemberInfo {
                    peer_id: m.peer_id,
                    pear_key: m.sid.to_string(),
                    nickname: m.nickname.clone(),
                    virtual_ip: m.vip.to_string(),
                    latency_ms: m.latency_ms,
                    online: m.online,
                    is_host: m.is_host,
                    is_self: m.key == 0,
                    bytes_in,
                    bytes_out,
                });
            }
        } else {
            for e in &self.roster {
                let is_self = e.steam_id == self.self_key;
                out.push(PearMemberInfo {
                    peer_id: e.peer_id,
                    pear_key: e.steam_id.to_string(),
                    nickname: e.nickname.clone(),
                    virtual_ip: e.vip.to_string(),
                    latency_ms: e.latency_ms,
                    online: e.online,
                    is_host: e.is_host,
                    is_self,
                    bytes_in: if is_self { self.rx_bytes } else { e.bytes_in },
                    bytes_out: if is_self { self.tx_bytes } else { e.bytes_out },
                });
            }
            if out.is_empty() && self.role == Role::Guest && self.my_peer_id != 0 {
                out.push(PearMemberInfo {
                    peer_id: self.my_peer_id,
                    pear_key: self.self_key.to_string(),
                    nickname: self.nickname.clone(),
                    virtual_ip: self.my_vip.to_string(),
                    latency_ms: 0,
                    online: true,
                    is_host: false,
                    is_self: true,
                    bytes_in: self.rx_bytes,
                    bytes_out: self.tx_bytes,
                });
            }
        }
        out.sort_by_key(|m| m.peer_id);
        out
    }

    fn assign_member(&mut self, key: u64) -> (u32, Ipv4Addr) {
        if let Some((peer_id, vip, at)) = self.assign_cache.get(&key) {
            if at.elapsed() < Duration::from_secs(30) {
                let pair = (*peer_id, *vip);
                self.assign_cache
                    .insert(key, (pair.0, pair.1, Instant::now()));
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
            .insert(key, (peer_id, vip, Instant::now()));
        (peer_id, vip)
    }

    fn roster_entries(&self) -> Vec<RosterEntry> {
        let mut out: Vec<RosterEntry> = self
            .members
            .values()
            .map(|m| {
                // 房主自己的成员项不累计流量，用引擎级计数器。
                let (bytes_in, bytes_out) = if m.key == 0 {
                    (self.rx_bytes, self.tx_bytes)
                } else {
                    (m.bytes_in, m.bytes_out)
                };
                RosterEntry {
                    peer_id: m.peer_id,
                    steam_id: m.sid,
                    nickname: m.nickname.clone(),
                    vip: m.vip,
                    online: m.online,
                    is_host: m.is_host,
                    latency_ms: m.latency_ms,
                    // Pear 不走 Steam SDR，没有中继路径概念。
                    via_relay: false,
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
        self.send_to_all(&bytes, None);
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
            self.roster
                .iter()
                .find(|e| e.vip == vip)
                .map(|e| e.peer_id)
        }
    }

    fn key_of_vip(&self, vip: Ipv4Addr) -> Option<u64> {
        if self.role == Role::Host {
            self.members
                .values()
                .find(|m| m.vip == vip && m.online)
                .map(|m| m.key)
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

fn engine_thread(rx: Receiver<Cmd>, pear_dir: PathBuf) {
    set_status(PearStatusInfo {
        ok: true,
        ready: false,
        message: "Pear 运行时已就绪，等待建房".to_string(),
        ..Default::default()
    });
    let mut engine = Engine::new(pear_dir);
    loop {
        let timeout = engine.tick_interval();
        match rx.recv_timeout(timeout) {
            Ok(cmd) => engine.handle_cmd(cmd),
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
        engine.tick();
    }
    engine.shutdown_room("Pear 线程结束");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn roster_entry(
        peer_id: u32,
        steam_id: u64,
        vip: Ipv4Addr,
        is_host: bool,
        latency_ms: u32,
    ) -> RosterEntry {
        RosterEntry {
            peer_id,
            steam_id,
            nickname: format!("peer-{peer_id}"),
            vip,
            online: true,
            is_host,
            latency_ms,
            via_relay: false,
            bytes_in: 0,
            bytes_out: 0,
        }
    }

    #[test]
    fn sidecar_event_parser_skips_malformed_lines() {
        let input = concat!(
            "{\"op\":\"ready\",\"selfKey\":\"abc\"}\n",
            "not-json\n",
            "{\"op\":\"peer\",\"id\":7,\"state\":\"open\"}\n",
            "{\"op\":\"data\"}\n",
            "{\"op\":\"data\",\"from\":3,\"data\":\"%%%\"}\n",
            "{\"op\":\"peer\",\"id\":7,\"state\":\"close\"}\n",
            "{\"op\":\"error\",\"message\":\"boom\"}\n",
        );
        let (tx, rx) = mpsc::channel();
        read_events(Cursor::new(input.as_bytes()), tx);
        let events: Vec<LinkEvent> = rx.try_iter().collect();

        // 非 JSON、缺字段、非法 base64 的行都应被安静跳过，不 panic。
        assert_eq!(events.len(), 5, "畸形行应跳过，正常事件按序保留");
        assert!(matches!(&events[0], LinkEvent::Ready { self_key } if self_key == "abc"));
        assert!(matches!(&events[1], LinkEvent::PeerOpen(7)));
        assert!(matches!(&events[2], LinkEvent::PeerClose(7)));
        assert!(matches!(&events[3], LinkEvent::Error(msg) if msg == "boom"));
        assert!(matches!(&events[4], LinkEvent::Exited));
    }

    #[test]
    fn guest_roster_backfills_host_latency_from_local_measurement() {
        let mut engine = Engine::new(PathBuf::new());
        engine.role = Role::Guest;
        engine.guest_host_latency_ms = 37;

        let body = proto::roster(&[
            roster_entry(1, 1, proto::HOST_VIP, true, 0),
            roster_entry(2, 2, proto::vip(2), false, 5),
        ]);
        let frame_bytes = proto::encode(
            proto::KIND_CONTROL,
            0,
            proto::HOST_VIP,
            proto::vip(100),
            &body,
        );
        let frame = proto::decode(&frame_bytes).expect("合法控制帧");
        engine.on_control(HOST_LINK_KEY, &frame);

        assert_eq!(engine.roster.len(), 2);
        let host = engine.roster.iter().find(|e| e.is_host).expect("房主条目");
        assert_eq!(
            host.latency_ms, 37,
            "房主下发的 0ms 应被客机实测值回填"
        );
        let peer = engine.roster.iter().find(|e| !e.is_host).expect("成员条目");
        assert_eq!(peer.latency_ms, 5, "其他成员延迟不应被改写");
    }

    #[test]
    fn peer_close_clears_guest_roster_and_presence_state() {
        let mut engine = Engine::new(PathBuf::new());
        engine.role = Role::Guest;
        engine.roster = vec![roster_entry(1, 1, proto::HOST_VIP, true, 0)];
        engine.guest_open = true;
        engine.hello_sent = true;
        engine.guest_ping_at = Some(Instant::now());
        engine.guest_host_latency_ms = 42;

        engine.on_link_event(LinkEvent::PeerClose(HOST_LINK_KEY));

        assert!(engine.roster.is_empty(), "房主链路断开后旧 Roster 必须清空");
        assert!(!engine.guest_open);
        assert!(!engine.hello_sent);
        assert!(engine.guest_ping_at.is_none());
        assert_eq!(engine.guest_host_latency_ms, 0);
        assert!(engine.reconnect_at.is_some(), "断开后应安排重连");
    }
}
