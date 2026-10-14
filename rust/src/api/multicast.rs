use flutter_rust_bridge::frb;
use tokio::io;
use tokio::net::UdpSocket;
use tokio::task::JoinHandle;
use tokio::time::{interval, Duration};
use tokio_util::sync::CancellationToken;
use std::net::SocketAddr;
use tokio::sync::Mutex;
use lazy_static::lazy_static;
use tokio::runtime::Runtime;

lazy_static! {
    static ref MULTICAST_RT: Runtime = Runtime::new().expect("创建 Tokio 运行时失败");
    static ref MULTICAST_SENDERS: Mutex<Vec<MulticastSender>> = Mutex::new(Vec::new());
}

#[frb(opaque)]
pub struct MulticastSender {
    multicast_addr: SocketAddr,
    bind_addr: String,
    data: Vec<u8>,
    interval_ms: u64,
    handle: Option<JoinHandle<()>>,
    cancel_token: Option<CancellationToken>,
}

impl MulticastSender {
    #[frb(ignore)]
    pub fn new(
        multicast_addr: impl Into<String>,
        port: u16,
        data: Vec<u8>,
        interval_ms: u64,
    ) -> io::Result<Self> {
        let multicast_addr: String = multicast_addr.into();
        let multicast_addr = format!("{}:{}", multicast_addr, port)
            .parse::<SocketAddr>()
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;

        Ok(Self {
            multicast_addr,
            bind_addr: "0.0.0.0:0".to_string(),
            data,
            interval_ms,
            handle: None,
            cancel_token: None,
        })
    }

    #[frb(ignore)]
    pub fn with_bind_addr(mut self, bind_addr: impl Into<String>) -> Self {
        self.bind_addr = bind_addr.into();
        self
    }

    pub async fn start(&mut self) -> io::Result<()> {
        if self.handle.is_some() {
            return Err(io::Error::new(io::ErrorKind::AlreadyExists, "组播已启动"));
        }

        let socket = UdpSocket::bind(&self.bind_addr).await?;
        // 关掉 loopback，避免本机发现器把刚注入的组播再吃回去（风暴）。
        let _ = socket.set_multicast_loop_v4(false);
        let _ = socket.set_multicast_ttl_v4(1);
        let multicast_addr = self.multicast_addr;
        let data = self.data.clone();
        let interval_ms = self.interval_ms;
        let cancel_token = CancellationToken::new();
        let cancel_token_clone = cancel_token.clone();

        let handle = tokio::spawn(async move {
            let mut ticker = interval(Duration::from_millis(interval_ms));
            loop {
                tokio::select! {
                    _ = cancel_token_clone.cancelled() => {
                        break;
                    }
                    _ = ticker.tick() => {
                        let _ = socket.send_to(&data, multicast_addr).await;
                    }
                }
            }
        });

        self.handle = Some(handle);
        self.cancel_token = Some(cancel_token);
        Ok(())
    }

    pub async fn stop(&mut self) {
        if let Some(cancel_token) = self.cancel_token.take() {
            cancel_token.cancel();
        }
        if let Some(handle) = self.handle.take() {
            let _ = handle.await;
        }
    }

    pub fn is_running(&self) -> bool {
        self.handle.is_some()
    }
}

// Flutter 友好的 API

/// 创建并启动一个组播发送器
/// 返回发送器索引，用于后续操作
pub fn create_multicast_sender(
    multicast_addr: String,
    port: u16,
    data: Vec<u8>,
    interval_ms: u64,
) -> Result<usize, String> {
    MULTICAST_RT.block_on(async move {
        let mut sender = match MulticastSender::new(multicast_addr.clone(), port, data, interval_ms) {
            Ok(s) => s,
            Err(e) => return Err(format!("创建组播发送器失败: {}", e)),
        };
        
        match sender.start().await {
            Ok(_) => {
                let mut senders = MULTICAST_SENDERS.lock().await;
                senders.push(sender);
                let index = senders.len() - 1;
                println!("组播发送器已启动: {}:{}, 间隔: {}ms, 索引: {}", multicast_addr, port, interval_ms, index);
                Ok(index)
            }
            Err(e) => Err(format!("启动组播发送器失败: {}", e))
        }
    })
}

/// 创建并启动一个组播发送器（带自定义绑定地址）
pub fn create_multicast_sender_with_bind(
    multicast_addr: String,
    port: u16,
    bind_addr: String,
    data: Vec<u8>,
    interval_ms: u64,
) -> Result<usize, String> {
    MULTICAST_RT.block_on(async move {
        let mut sender = match MulticastSender::new(multicast_addr.clone(), port, data, interval_ms) {
            Ok(s) => s.with_bind_addr(bind_addr.clone()),
            Err(e) => return Err(format!("创建组播发送器失败: {}", e)),
        };
        
        match sender.start().await {
            Ok(_) => {
                let mut senders = MULTICAST_SENDERS.lock().await;
                senders.push(sender);
                let index = senders.len() - 1;
                println!("组播发送器已启动: {}:{}, 绑定: {}, 间隔: {}ms, 索引: {}",
                    multicast_addr, port, bind_addr, interval_ms, index);
                Ok(index)
            }
            Err(e) => Err(format!("启动组播发送器失败: {}", e))
        }
    })
}

/// 停止指定索引的组播发送器
pub fn stop_multicast_sender(index: usize) -> Result<(), String> {
    MULTICAST_RT.block_on(async move {
        let mut senders = MULTICAST_SENDERS.lock().await;
        
        if index >= senders.len() {
            return Err(format!("无效的发送器索引: {}", index));
        }
        
        senders[index].stop().await;
        println!("组播发送器已停止，索引: {}", index);
        Ok(())
    })
}

/// 停止所有组播发送器
pub fn stop_all_multicast_senders() -> Result<(), String> {
    MULTICAST_RT.block_on(async move {
        let mut senders = MULTICAST_SENDERS.lock().await;
        if senders.is_empty() {
            return Ok(());
        }
        let n = senders.len();
        for sender in senders.iter_mut() {
            sender.stop().await;
        }
        senders.clear();
        println!("已停止 {n} 个组播发送器");
        Ok(())
    })
}

/// 获取所有正在运行的组播发送器数量
pub fn get_multicast_sender_count() -> usize {
    MULTICAST_RT.block_on(async move {
        let senders = MULTICAST_SENDERS.lock().await;
        senders.len()
    })
}

/// 检查指定发送器是否正在运行
pub fn is_multicast_sender_running(index: usize) -> bool {
    MULTICAST_RT.block_on(async move {
        let senders = MULTICAST_SENDERS.lock().await;
        
        if index >= senders.len() {
            return false;
        }
        
        senders[index].is_running()
    })
}

// ---------- 通用局域网发现：UDP 组播 + 可插拔 parser ----------

use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr};
use std::sync::Mutex as StdMutex;
use std::time::{SystemTime, UNIX_EPOCH};

/// 组播/解析得到的本机开放游戏（与具体游戏解耦）。
#[derive(Clone)]
pub struct LanGameDiscovery {
    /// 解析器名，如 `minecraft_motd`。
    pub parser: String,
    pub game_port: u16,
    pub motd: String,
    pub source_ip: String,
    pub seen_unix_ms: u64,
}

struct LanGameListener {
    handle: Option<JoinHandle<()>>,
    cancel: Option<CancellationToken>,
}

lazy_static! {
    static ref LAN_LISTENERS: Mutex<Vec<LanGameListener>> = Mutex::new(Vec::new());
    /// key = `parser:port`
    static ref LAN_DISCOVERIES: StdMutex<HashMap<String, LanGameDiscovery>> =
        StdMutex::new(HashMap::new());
}

fn now_unix_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn local_ipv4_set() -> std::collections::HashSet<Ipv4Addr> {
    let mut set = std::collections::HashSet::new();
    if let Ok(list) = local_ip_address::list_afinet_netifas() {
        for (_, ip) in list {
            if let IpAddr::V4(v4) = ip {
                if !v4.is_loopback() {
                    set.insert(v4);
                }
            }
        }
    }
    set
}

fn is_own_source(src: IpAddr, locals: &std::collections::HashSet<Ipv4Addr>) -> bool {
    match src {
        // 回环 = 本机 127 注入，不参与发现（防风暴）；真 MC 来自网卡 IP。
        IpAddr::V4(v4) => !v4.is_loopback() && locals.contains(&v4),
        IpAddr::V6(_) => false,
    }
}

fn is_own_inject_payload(data: &[u8], injects: &[Vec<u8>]) -> bool {
    injects.iter().any(|p| p.as_slice() == data)
}

/// 可插拔载荷解析：返回 (显示名/motd, 游戏端口)。
fn parse_lan_payload(parser: &str, data: &[u8]) -> Option<(String, u16)> {
    match parser {
        "minecraft_motd" => parse_minecraft_motd(data),
        // 后续：factorheim_query / source_engine / custom_json ...
        _ => None,
    }
}

/// 解析 MC LAN：`[MOTD]...[/MOTD][AD]port[/AD]`
fn parse_minecraft_motd(data: &[u8]) -> Option<(String, u16)> {
    let s = String::from_utf8_lossy(data);
    let motd = extract_tag(&s, "[MOTD]", "[/MOTD]")?;
    let ad = extract_tag(&s, "[AD]", "[/AD]")?;
    let port: u16 = ad.trim().parse().ok()?;
    if port == 0 {
        return None;
    }
    Some((motd.trim().to_string(), port))
}

fn extract_tag<'a>(s: &'a str, open: &str, close: &str) -> Option<&'a str> {
    let start = s.find(open)? + open.len();
    let rest = s.get(start..)?;
    let end = rest.find(close)?;
    Some(&rest[..end])
}

async fn bind_udp_reuse(addr: &str) -> io::Result<UdpSocket> {
    use socket2::{Domain, Protocol, Socket, Type};
    let std_addr: std::net::SocketAddr = addr
        .parse()
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    let domain = if std_addr.is_ipv4() {
        Domain::IPV4
    } else {
        Domain::IPV6
    };
    let socket = Socket::new(domain, Type::DGRAM, Some(Protocol::UDP))?;
    socket.set_reuse_address(true)?;
    #[cfg(unix)]
    socket.set_reuse_port(true)?;
    socket.bind(&socket2::SockAddr::from(std_addr))?;
    socket.set_nonblocking(true)?;
    UdpSocket::from_std(std::net::UdpSocket::from(socket))
}

/// 启动通用 UDP 组播监听；`parser` 决定如何从载荷提取游戏端口。
///
/// 已知 parser：`minecraft_motd`。仅收录本机网卡来源（不含回环/自身注入）。
pub fn start_udp_multicast_lan_listener(
    multicast_addr: String,
    port: u16,
    parser: String,
) -> Result<usize, String> {
    let parser = parser.trim().to_lowercase();
    if parser.is_empty() {
        return Err("parser 不能为空".into());
    }
    if !matches!(parser.as_str(), "minecraft_motd") {
        return Err(format!("未知组播 parser: {parser}（请在内核 parse_lan_payload 注册）"));
    }

    MULTICAST_RT.block_on(async move {
        let group: Ipv4Addr = multicast_addr
            .parse()
            .map_err(|e| format!("无效组播地址: {}", e))?;
        let listen = format!("0.0.0.0:{}", port);
        let socket = bind_udp_reuse(&listen)
            .await
            .map_err(|e| format!("绑定组播监听失败 {}: {}", listen, e))?;
        socket
            .join_multicast_v4(group, Ipv4Addr::UNSPECIFIED)
            .map_err(|e| format!("加入组播失败: {}", e))?;
        let _ = socket.set_multicast_loop_v4(true);

        let cancel = CancellationToken::new();
        let cancel_clone = cancel.clone();
        let locals = local_ipv4_set();
        let parser_clone = parser.clone();

        let handle = tokio::spawn(async move {
            let mut buf = [0u8; 2048];
            loop {
                tokio::select! {
                    _ = cancel_clone.cancelled() => break,
                    r = socket.recv_from(&mut buf) => {
                        let Ok((n, src)) = r else { continue };
                        if !is_own_source(src.ip(), &locals) {
                            continue;
                        }
                        let injects = {
                            let senders = MULTICAST_SENDERS.lock().await;
                            senders
                                .iter()
                                .filter(|s| s.is_running())
                                .map(|s| s.data.clone())
                                .collect::<Vec<_>>()
                        };
                        if is_own_inject_payload(&buf[..n], &injects) {
                            continue;
                        }
                        let Some((motd, game_port)) =
                            parse_lan_payload(&parser_clone, &buf[..n])
                        else {
                            continue;
                        };
                        let seen = now_unix_ms();
                        let key = format!("{}:{}", parser_clone, game_port);
                        if let Ok(mut map) = LAN_DISCOVERIES.lock() {
                            map.insert(
                                key,
                                LanGameDiscovery {
                                    parser: parser_clone.clone(),
                                    game_port,
                                    motd,
                                    source_ip: src.ip().to_string(),
                                    seen_unix_ms: seen,
                                },
                            );
                        }
                    }
                }
            }
        });

        let mut listeners = LAN_LISTENERS.lock().await;
        listeners.push(LanGameListener {
            handle: Some(handle),
            cancel: Some(cancel),
        });
        let index = listeners.len() - 1;
        println!(
            "UDP 组播监听已启动: {}:{} parser={} index={}",
            multicast_addr, port, parser, index
        );
        Ok(index)
    })
}

/// 兼容旧名：MC MOTD 组播监听。
pub fn start_minecraft_lan_listener(
    multicast_addr: String,
    port: u16,
) -> Result<usize, String> {
    start_udp_multicast_lan_listener(multicast_addr, port, "minecraft_motd".into())
}

/// 拉取当前发现到的本机开放游戏（自动丢掉 20s 未再见的条目）。
pub fn poll_lan_game_discoveries() -> Vec<LanGameDiscovery> {
    let now = now_unix_ms();
    let mut out = Vec::new();
    if let Ok(mut map) = LAN_DISCOVERIES.lock() {
        map.retain(|_, v| now.saturating_sub(v.seen_unix_ms) < 20_000);
        out.extend(map.values().cloned());
    }
    out.sort_by(|a, b| {
        a.parser
            .cmp(&b.parser)
            .then_with(|| a.game_port.cmp(&b.game_port))
    });
    out
}

/// 停止所有局域网组播监听并清空发现缓存。
pub fn stop_all_lan_game_listeners() -> Result<(), String> {
    MULTICAST_RT.block_on(async move {
        let mut listeners = LAN_LISTENERS.lock().await;
        for (i, l) in listeners.iter_mut().enumerate() {
            if let Some(c) = l.cancel.take() {
                c.cancel();
            }
            if let Some(h) = l.handle.take() {
                let _ = h.await;
            }
            println!("组播监听已停止 index={}", i);
        }
        listeners.clear();
        if let Ok(mut map) = LAN_DISCOVERIES.lock() {
            map.clear();
        }
        Ok(())
    })
}
