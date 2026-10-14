use easytier::common::config::{
    ConfigFileControl, ConfigLoader, TomlConfigLoader, normalize_secure_mode_config,
};
pub use easytier::common::global_ctx::{EventBusSubscriber, GlobalCtxEvent};
use easytier::instance::factory::{NativeInstanceManager, native_cli_instance_manager};
pub use easytier::proto;
pub use easytier::proto::api::instance::{PeerRoutePair, Route};
pub use easytier::proto::common::NatType;
use lazy_static::lazy_static;
use tokio::runtime::Runtime;
use uuid::Uuid;

const LOCAL_SYNTHETIC_PEER_ID: u32 = 0;

lazy_static! {
    static ref RT: Runtime = Runtime::new().expect("failed to create tokio runtime");
    static ref MANAGER: NativeInstanceManager = native_cli_instance_manager();
}

fn parse_instance_id(instance_id: &str) -> Result<Uuid, String> {
    Uuid::parse_str(instance_id).map_err(|e| format!("invalid instance_id: {}", e))
}
/// wintun 虚拟网卡默认走「自动跃点」：wintun 驱动静态上报 100Gbps 链路速率，
/// Windows 自动跃点表对 >=100Gbps 接口给出跃点 5。这里显式压到 1（合法最小值；
/// 注意 metric=0 会被 netsh 解释为「恢复自动跃点」，等于没改）。
/// 网卡由 easytier 异步创建，run_network_instance 返回时可能尚未出现，
/// 需轮询等待；设置失败只记日志，不影响启动流程。
#[cfg(target_os = "windows")]
fn spawn_set_nic_metric_task(instance_id: &str, dev_name: &str) {
    if dev_name.is_empty() {
        return;
    }
    let instance_id = instance_id.to_string();
    let dev_name = dev_name.to_string();
    RT.spawn(async move {
        let max_attempts = 30u32;
        for attempt in 1..=max_attempts {
            let name = dev_name.clone();
            let ok = tokio::task::spawn_blocking(move || set_interface_metric_blocking(&name))
                .await
                .unwrap_or(false);

            if ok {
                emit_core_log(
                    &instance_id,
                    &format!("nic {} interface metric set to 1", dev_name),
                );
                return;
            }
            if attempt < max_attempts {
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
            }
        }
        emit_core_log(
            &instance_id,
            &format!("nic {} interface metric set to 1 failed: interface not found", dev_name),
        );
    });
}

#[cfg(target_os = "windows")]
fn set_interface_metric_blocking(dev_name: &str) -> bool {
    use std::os::windows::process::CommandExt;
    use std::process::Command;
    // CREATE_NO_WINDOW：GUI 进程派生控制台程序（netsh）默认会弹黑窗，必须显式抑制。
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let set_metric = |proto: &str| -> bool {
        Command::new("netsh.exe")
            .creation_flags(CREATE_NO_WINDOW)
            .args([
                "interface",
                proto,
                "set",
                "interface",
                // 这里的标签必须是 interface=（不是 name=）；
                // name= 会被 netsh 拒绝（"'name' 不是这个指令的有效参数"），
                // 导致跃点设置静默失败、一直停留在 wintun 自动跃点 5。
                &format!("interface=\"{}\"", dev_name),
                "metric=1",
            ])
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    };
    let v4 = set_metric("ipv4");
    let _v6 = set_metric("ipv6");
    // IPv6 尽力而为；IPv4 成功即视为网卡已出现且跃点已生效。
    v4
}

async fn get_instance_info(
    instance_id: &str,
) -> Result<easytier::proto::api::manage::NetworkInstanceRunningInfo, String> {
    let id = parse_instance_id(instance_id)?;
    MANAGER
        .network_info(id)
        .await
        .ok_or_else(|| "instance not found".to_string())
}

fn peer_conn_info_to_string(p: proto::api::instance::PeerConnInfo) -> String {
    format!(
        "my_peer_id: {}, dst_peer_id: {}, tunnel_info: {:?}",
        p.my_peer_id, p.peer_id, p.tunnel
    )
}

use crate::frb_generated::StreamSink;
use std::sync::Mutex;

lazy_static! {
    static ref CORE_LOG_SINK: Mutex<Option<StreamSink<CoreLogEventC>>> = Mutex::new(None);
}

/// EasyTier 内核日志事件（替代 UDP 127.0.0.1:9999）。
#[derive(Debug, Clone)]
pub struct CoreLogEventC {
    pub instance_id: String,
    pub message: String,
}

/// Dart 侧订阅内核日志流；后订阅覆盖前订阅。
pub fn subscribe_core_logs(sink: StreamSink<CoreLogEventC>) {
    if let Ok(mut guard) = CORE_LOG_SINK.lock() {
        *guard = Some(sink);
    }
}

fn emit_core_log(instance_id: &str, message: &str) {
    let Ok(guard) = CORE_LOG_SINK.lock() else {
        return;
    };
    let Some(sink) = guard.as_ref() else {
        return;
    };
    let _ = sink.add(CoreLogEventC {
        instance_id: instance_id.to_string(),
        message: message.to_string(),
    });
}

fn event_to_message(e: GlobalCtxEvent) -> Option<String> {
    match e {
        GlobalCtxEvent::PeerAdded(p) => Some(format!("peer added. peer_id: {}", p)),
        GlobalCtxEvent::PeerRemoved(p) => Some(format!("peer removed. peer_id: {}", p)),
        GlobalCtxEvent::PeerConnAdded(p) => {
            Some(format!("peer connection added. conn_info: {}", peer_conn_info_to_string(p)))
        }
        GlobalCtxEvent::PeerConnRemoved(p) => {
            Some(format!(
                "peer connection removed. conn_info: {}",
                peer_conn_info_to_string(p)
            ))
        }
        GlobalCtxEvent::ListenerAddFailed(p, msg) => {
            Some(format!("listener add failed. listener: {}, msg: {}", p, msg))
        }
        GlobalCtxEvent::ListenerAcceptFailed(p, msg) => {
            Some(format!("listener accept failed. listener: {}, msg: {}", p, msg))
        }
        GlobalCtxEvent::ListenerAdded(p) => {
            if p.scheme() == "ring" {
                None
            } else {
                Some(format!("listener added. listener: {}", p))
            }
        }
        GlobalCtxEvent::ConnectionAccepted(local, remote) => {
            Some(format!("connection accepted. local: {}, remote: {}", local, remote))
        }
        GlobalCtxEvent::ConnectionError(local, remote, err) => {
            Some(format!(
                "connection error. local: {}, remote: {}, err: {}",
                local, remote, err
            ))
        }
        GlobalCtxEvent::TunDeviceReady(dev) => Some(format!("tun device ready. dev: {}", dev)),
        GlobalCtxEvent::TunDeviceError(err) => Some(format!("tun device error. err: {}", err)),
        GlobalCtxEvent::Connecting(dst) => Some(format!("connecting to peer. dst: {}", dst)),
        GlobalCtxEvent::ConnectError(dst, ip_version, err) => Some(format!(
            "connect error. dst: {}, ip_version: {}, err: {}",
            dst, ip_version, err
        )),
        GlobalCtxEvent::VpnPortalStarted(portal) => {
            Some(format!("vpn portal started. portal: {}", portal))
        }
        GlobalCtxEvent::VpnPortalClientConnected(portal, client_addr) => Some(format!(
            "vpn portal client connected. portal: {}, client_addr: {}",
            portal, client_addr
        )),
        GlobalCtxEvent::VpnPortalClientDisconnected(portal, client_addr) => Some(format!(
            "vpn portal client disconnected. portal: {}, client_addr: {}",
            portal, client_addr
        )),
        GlobalCtxEvent::DhcpIpv4Changed(old, new) => {
            Some(format!("dhcp ip changed. old: {:?}, new: {:?}", old, new))
        }
        GlobalCtxEvent::DhcpIpv4Conflicted(ip) => Some(format!("dhcp ip conflict. ip: {:?}", ip)),
        GlobalCtxEvent::DhcpIpv6Changed(old, new) => {
            Some(format!("dhcp ipv6 changed. old: {:?}, new: {:?}", old, new))
        }
        GlobalCtxEvent::DhcpIpv6Conflicted(ip) => {
            Some(format!("dhcp ipv6 conflict. ip: {:?}", ip))
        }
        GlobalCtxEvent::PortForwardAdded(cfg) => {
            Some(format!("port forward added. cfg: {:?}", cfg))
        }
        GlobalCtxEvent::ListenerPortMappingEstablished {
            local_listener,
            mapped_listener,
            backend,
        } => Some(format!(
            "listener port mapping established. local: {}, mapped: {}, backend: {}",
            local_listener, mapped_listener, backend
        )),
        GlobalCtxEvent::PublicIpv6Changed(old, new) => {
            Some(format!("public ipv6 changed. old: {:?}, new: {:?}", old, new))
        }
        GlobalCtxEvent::PublicIpv6RoutesUpdated(added, removed) => Some(format!(
            "public ipv6 routes updated. added: {:?}, removed: {:?}",
            added, removed
        )),
        GlobalCtxEvent::UdpBroadcastRelayStartResult {
            capture_backend,
            error,
        } => Some(format!(
            "udp broadcast relay start result. backend: {:?}, error: {:?}",
            capture_backend, error
        )),
        GlobalCtxEvent::CredentialChanged => Some("credential changed".to_string()),
        GlobalCtxEvent::ConfigPatched(_) => None,
        GlobalCtxEvent::ProxyCidrsUpdated(_, _) => None,
    }
}

/// Forward EasyTier events to Dart via [subscribe_core_logs].
fn spawn_instance_event_forwarder(
    events: EventBusSubscriber,
    instance_id: String,
) -> tokio::task::JoinHandle<()> {
    spawn_event_forwarder(events, instance_id)
}

fn spawn_event_forwarder(
    mut events: EventBusSubscriber,
    instance_id: String,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        loop {
            match events.recv().await {
                Ok(e) => {
                    if let Some(msg) = event_to_message(e) {
                        emit_core_log(&instance_id, &msg);
                    }
                }
                Err(err) => {
                    eprintln!("event receive error: {:?}", err);
                    match err {
                        tokio::sync::broadcast::error::RecvError::Closed => {
                            emit_core_log(
                                &instance_id,
                                "event channel closed; stop handling events",
                            );
                            break;
                        }
                        tokio::sync::broadcast::error::RecvError::Lagged(n) => {
                            let msg = format!("event lagged, dropped {} events", n);
                            eprintln!("{}", msg);
                            emit_core_log(&instance_id, &msg);
                        }
                    }
                }
            }
        }
    })
}

pub fn easytier_version() -> Result<String, String> {
    Ok(easytier::VERSION.to_string())
}

pub async fn is_easytier_running(instance_id: String) -> bool {
    let Ok(id) = parse_instance_id(&instance_id) else {
        return false;
    };
    MANAGER.instance(id).is_some_and(|instance| instance.is_ready())
}

#[derive(Debug)]
pub struct NodeHopStats {
    pub peer_id: u32,
    pub target_ip: String,
    pub latency_ms: f64,
    pub packet_loss: f32,
    pub node_name: String,
}

#[derive(Debug)]
pub struct KVNodeConnectionStats {
    pub conn_type: String,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub rx_packets: u64,
    pub tx_packets: u64,
}

#[derive(Debug)]
pub struct KVNodeInfo {
    pub peer_id: u32,
    pub hostname: String,
    pub ipv4: String,
    /// 虚拟网 IPv6（含前缀长度），与 `Route.ipv6_addr` 一致；无分配时为空串。
    pub ipv6: String,
    pub latency_ms: f64,
    pub nat: String,
    pub hops: Vec<NodeHopStats>,
    pub loss_rate: f32,
    pub connections: Vec<KVNodeConnectionStats>,
    pub tunnel_proto: String,
    pub conn_type: String,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub version: String,
    pub cost: i32,
    /// Noise 远端静态公钥（base64）；空串表示未知。用于房主按凭据踢人。
    pub remote_static_pubkey_b64: String,
    /// 是否为凭据节点（无 network_secret）。
    pub is_credential_peer: bool,
}

#[derive(Debug)]
pub struct KVNetworkStatus {
    pub total_nodes: usize,
    pub nodes: Vec<KVNodeInfo>,
}

pub async fn set_tun_fd(instance_id: String, fd: i32) -> Result<(), String> {
    let id = parse_instance_id(&instance_id)?;
    MANAGER
        .attach_tun_fd(id, fd)
        .map_err(|e| format!("set_tun_fd failed: {}", e))
}

pub async fn create_instance(config_toml: String, watch_event: bool) -> Result<String, String> {
    // Keep work on the shared RT (same as the old JoinHandle path), then await
    // here so Dart gets a plain String without FRB opaque handles.
    RT.spawn(async move {
        let cfg = TomlConfigLoader::new_from_str(&config_toml)
            .map_err(|e| format!("invalid config toml: {}", e))?;
        let instance_id = cfg.get_id();
        let instance_id_str = instance_id.to_string();

        // EasyTier 加载 TOML 时不会自动补全 secure_mode 密钥；enabled 但未写
        // local_private_key 时连公共节点会报 "local private key is not set"。
        if let Some(sm) = cfg.get_secure_mode() {
            if sm.enabled {
                let had_priv = sm.local_private_key.is_some();
                let processed = normalize_secure_mode_config(sm)
                    .map_err(|e| format!("invalid secure_mode: {}", e))?;
                cfg.set_secure_mode(Some(processed));
                if !had_priv {
                    emit_core_log(
                        &instance_id_str,
                        "secure_mode: generated local keypair (missing in toml)",
                    );
                }
            }
        }

        let network_identity = cfg.get_network_identity();
        let hostname = cfg.get_hostname();
        let dhcp = cfg.get_dhcp();
        let ipv4 = cfg.get_ipv4().map(|ip| ip.to_string()).unwrap_or_else(|| "none".to_string());
        let listeners = cfg.get_listeners()
            .map(|l| l.iter().map(|u| u.to_string()).collect::<Vec<_>>().join(", "))
            .unwrap_or_else(|| "none".to_string());
        let peers = cfg
            .get_peers()
            .iter()
            .map(|p| p.uri.to_string())
            .collect::<Vec<_>>()
            .join(", ");
        let secure_enabled = cfg
            .get_secure_mode()
            .map(|sm| sm.enabled)
            .unwrap_or(false);
        let secure_has_key = cfg
            .get_secure_mode()
            .and_then(|sm| sm.local_private_key)
            .is_some();

        let config_msg = format!(
            "instance starting. instance_id: {}, network_name: {}, hostname: {}, dhcp: {}, ipv4: {}, secure_mode: enabled={}, has_local_key={}, listeners: [{}], peers: [{}]",
            instance_id,
            network_identity.network_name,
            hostname,
            dhcp,
            ipv4,
            secure_enabled,
            secure_has_key,
            listeners,
            peers
        );
        emit_core_log(&instance_id_str, &config_msg);

        let dev_name = cfg.get_flags().dev_name;
        MANAGER
            .run_network_instance(cfg, ConfigFileControl::STATIC_CONFIG)
            .map_err(|e| format!("start instance failed: {}", e))?;

        // 等虚拟网卡出现后把接口跃点压到 1（wintun 自动跃点为 5）；失败不影响启动。
        #[cfg(target_os = "windows")]
        spawn_set_nic_metric_task(&instance_id_str, &dev_name);
        #[cfg(not(target_os = "windows"))]
        let _ = dev_name;

        // 事件订阅尽早挂上，启动失败（如 Wintun / 静态 ipv4）仍能进 GUI。
        // 不在此强制等 astral_app_rpc：客户端启动路径不依赖它；需要 RPC 的调用方自行重试。
        if watch_event {
            if let Some(instance) = MANAGER.instance(instance_id) {
                if let Some(subscriber) =
                    easytier::instance::factory::subscribe_native_instance_event(&instance)
                {
                    spawn_instance_event_forwarder(subscriber, instance_id_str.clone());
                }
            }
        }

        Ok(instance_id_str)
    })
    .await
    .map_err(|e| format!("join handle error: {}", e))?
}

pub async fn close_instance(instance_id: String) -> Result<(), String> {
    // delete_network_instances 需要在 tokio runtime 上下文中执行；统一搬到共享 RT。
    RT.spawn(async move {
        let id = parse_instance_id(&instance_id)?;
        MANAGER
            .delete_network_instances(vec![id])
            .await
            .map_err(|e| format!("delete instance failed: {}", e))?;
        Ok(())
    })
    .await
    .map_err(|e| format!("join handle error: {}", e))?
}

/// Build peer/route pairs from a running-info snapshot (shared by FRB + astral-core).
#[flutter_rust_bridge::frb(ignore)]
pub fn peer_route_pairs_from_info(
    info: easytier::proto::api::manage::NetworkInstanceRunningInfo,
) -> Vec<PeerRoutePair> {
    let mut pairs = if info.peer_route_pairs.is_empty() {
        use easytier::proto::api::instance::list_peer_route_pair;
        list_peer_route_pair(info.peers.clone(), info.routes.clone())
    } else {
        info.peer_route_pairs
    };

    let mut route_peer_ids: std::collections::HashSet<u32> = pairs
        .iter()
        .filter_map(|p| p.route.as_ref().map(|r| r.peer_id))
        .collect();

    for peer in &info.peers {
        if !route_peer_ids.contains(&peer.peer_id) {
            pairs.push(PeerRoutePair {
                route: None,
                peer: Some(peer.clone()),
            });
            route_peer_ids.insert(peer.peer_id);
        }
    }

    if let Some(my_node_info) = &info.my_node_info {
        let my_peer_id = LOCAL_SYNTHETIC_PEER_ID;

        // 本机虚拟 IPv6：优先取 EasyTier 归一化后的 `my_node_info.virtual_ipv6`
        // （即本机 DHCPv6 分配结果）；老版本没有该字段时回退到 routes 表。
        // 注意 v4 一直用 `my_node_info.virtual_ipv4`——routes 表含的是其它 peer，
        // 不含本机行，所以旧写法在本机上取不到 v6。
        let my_ipv6 = my_node_info.virtual_ipv6.clone().or_else(|| {
            info.routes
                .iter()
                .find(|r| r.peer_id == my_node_info.peer_id)
                .and_then(|r| r.ipv6_addr.clone())
        });

        let my_route = Route {
            peer_id: my_peer_id,
            ipv4_addr: my_node_info.virtual_ipv4.clone(),
            ipv6_addr: my_ipv6,
            next_hop_peer_id: my_peer_id,
            cost: 0,
            path_latency: 0,
            proxy_cidrs: vec![],
            hostname: my_node_info.hostname.clone(),
            stun_info: my_node_info.stun_info.clone(),
            inst_id: "local".to_string(),
            version: my_node_info.version.clone(),
            feature_flag: None,
            next_hop_peer_id_latency_first: None,
            cost_latency_first: None,
            path_latency_latency_first: None,
            public_ipv6_addr: None,
            ipv6_public_addr_prefix: None,
        };

        pairs.push(PeerRoutePair {
            route: Some(my_route),
            peer: None,
        });
    }

    pairs
}

pub async fn get_network_status(instance_id: String) -> KVNetworkStatus {
    let info = match get_instance_info(&instance_id).await {
        Ok(info) => info,
        Err(_) => {
            return KVNetworkStatus {
                total_nodes: 0,
                nodes: vec![],
            };
        }
    };
    network_status_from_info(info)
}

/// Map running info → KVNetworkStatus (used by FRB and astral-core JSON control).
#[flutter_rust_bridge::frb(ignore)]
pub fn network_status_from_info(
    info: easytier::proto::api::manage::NetworkInstanceRunningInfo,
) -> KVNetworkStatus {
    let pairs = peer_route_pairs_from_info(info);

    let routes_by_peer: std::collections::HashMap<u32, Route> = pairs
        .iter()
        .filter_map(|p| p.route.clone())
        .map(|r| (r.peer_id, r))
        .collect();

    let mut nodes: Vec<KVNodeInfo> = Vec::new();
    for p in &pairs {
        let Some(route) = p.route.clone() else {
            continue;
        };

        let lat_ms = if route.cost == 1 {
            p.get_latency_ms().unwrap_or(0.0)
        } else {
            route.path_latency_latency_first.unwrap_or(0) as f64
        };

        let loss_percent = p.get_loss_rate().unwrap_or(0.0) * 100.0;
        let ipv4 = route
            .ipv4_addr
            .as_ref()
            .and_then(|ip| ip.address.clone())
            .map(|ip| ip.to_string())
            .unwrap_or_default();

        let ipv6 = route
            .ipv6_addr
            .as_ref()
            .map(|addr| addr.to_string())
            .unwrap_or_default();

        let tunnel_proto = p.get_conn_protos().unwrap_or_default().join(",");
        let conn_type = p
            .get_conn_protos()
            .unwrap_or_default()
            .into_iter()
            .next()
            .unwrap_or_else(|| p.get_udp_nat_type());

        let hops = if route.cost <= 1
            || route.inst_id == "local"
            || route.peer_id == LOCAL_SYNTHETIC_PEER_ID
        {
            Vec::new()
        } else {
            collect_relay_hops(&routes_by_peer, route.next_hop_peer_id, route.peer_id)
        };

        let flag_credential = route
            .feature_flag
            .as_ref()
            .map(|f| f.is_credential_peer)
            .unwrap_or(false);

        let mut remote_static_pubkey_b64 = String::new();
        let mut identity_credential = false;
        if let Some(peer) = &p.peer {
            for conn in &peer.conns {
                if remote_static_pubkey_b64.is_empty() && !conn.noise_remote_static_pubkey.is_empty()
                {
                    use base64::Engine;
                    remote_static_pubkey_b64 =
                        base64::engine::general_purpose::STANDARD.encode(&conn.noise_remote_static_pubkey);
                }
                if conn.peer_identity_type
                    == easytier::proto::peer_rpc::PeerIdentityType::Credential as i32
                {
                    identity_credential = true;
                }
            }
        }

        let mut node_info = KVNodeInfo {
            peer_id: route.peer_id,
            hostname: route.hostname.clone(),
            ipv4,
            ipv6,
            latency_ms: lat_ms,
            nat: p.get_udp_nat_type(),
            hops,
            loss_rate: loss_percent as f32,
            connections: vec![],
            tunnel_proto,
            conn_type,
            rx_bytes: p.get_rx_bytes().unwrap_or(0),
            tx_bytes: p.get_tx_bytes().unwrap_or(0),
            version: if route.version.is_empty() {
                "unknown".to_string()
            } else {
                route.version
            },
            cost: route.cost,
            remote_static_pubkey_b64,
            is_credential_peer: flag_credential || identity_credential,
        };

        if route.inst_id == "local" || route.peer_id == LOCAL_SYNTHETIC_PEER_ID {
            node_info.conn_type = "Local".to_string();
            if node_info.tunnel_proto.is_empty() {
                node_info.tunnel_proto = "-".to_string();
            }
        }

        if let Some(peer) = &p.peer {
            for conn in &peer.conns {
                if let Some(stats) = &conn.stats {
                    let conn_type = conn
                        .tunnel
                        .as_ref()
                        .map(|t| t.tunnel_type.clone())
                        .unwrap_or_else(|| "unknown".to_string());
                    node_info.connections.push(KVNodeConnectionStats {
                        conn_type,
                        rx_bytes: stats.rx_bytes,
                        tx_bytes: stats.tx_bytes,
                        rx_packets: stats.rx_packets,
                        tx_packets: stats.tx_packets,
                    });
                }
            }
        }

        nodes.push(node_info);
    }

    nodes.sort_by(|a, b| a.peer_id.cmp(&b.peer_id));
    nodes.dedup_by(|a, b| a.peer_id == b.peer_id);

    KVNetworkStatus {
        total_nodes: nodes.len(),
        nodes,
    }
}

fn collect_relay_hops(
    routes_by_peer: &std::collections::HashMap<u32, Route>,
    mut next: u32,
    target: u32,
) -> Vec<NodeHopStats> {
    let mut hops = Vec::new();
    let mut visited = std::collections::HashSet::new();
    while next != 0 && next != target && visited.insert(next) {
        let Some(route) = routes_by_peer.get(&next) else {
            break;
        };
        let ip = route
            .ipv4_addr
            .as_ref()
            .and_then(|a| a.address.as_ref())
            .map(|a| a.to_string())
            .unwrap_or_default();
        hops.push(NodeHopStats {
            peer_id: next,
            target_ip: ip,
            latency_ms: 0.0,
            packet_loss: 0.0,
            node_name: route.hostname.clone(),
        });
        let step = route.next_hop_peer_id;
        if step == next {
            break;
        }
        next = step;
    }
    hops
}

/// Eagerly initialize the shared Tokio runtime used by EasyTier bindings.
pub(crate) fn ensure_runtime() {
    lazy_static::initialize(&RT);
}

// ============================================================================
// Astral application-level peer RPC bindings.
//
// Thin Dart-friendly wrappers around `easytier::peers::astral_app_rpc`. The
// underlying RPC surface is intentionally tiny (Call / Notify / Ping) and
// dispatches business flows by `channel` + opaque `payload` bytes; see
// `easytier/src/proto/astral_rpc.proto` for the wire contract.
//
// Multi-instance: every method takes the instance UUID string so several
// running networks can be addressed independently.
// ============================================================================

use easytier::peers::astral_app_rpc as app_rpc;

/// Mirrors `easytier::peers::astral_app_rpc::status` so callers don't have to
/// pull the underlying crate just to read constants.
pub mod app_rpc_status {
    pub const OK: i32 = 0;
    pub const NO_SUBSCRIBER: i32 = -1;
    pub const REPLY_TIMEOUT: i32 = -2;
    pub const SERVICE_DROPPED: i32 = -3;
}

/// Result of [`app_call`] — directly maps `AppCallResponse` to a Dart record.
#[derive(Debug, Clone)]
pub struct AppCallResultC {
    pub status: i32,
    pub error_msg: String,
    pub payload: Vec<u8>,
}

/// Discriminator for [`AppInboundEventC`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AppInboundKindC {
    /// Request expecting a reply. Receiver MUST call [`app_call_reply`] with
    /// the carried `token`, otherwise the remote caller observes
    /// `app_rpc_status::REPLY_TIMEOUT` after the receiver-side timeout
    /// (default 30s, configured in EasyTier).
    Call,
    /// Fire-and-forget notification (the sender already received an RPC-layer
    /// ack; this event is informational on the receiver side). For `Notify`
    /// events `request_id` and `token` are always 0.
    Notify,
}

/// Inbound event delivered through [`subscribe_app_inbound`].
///
/// Modelled as a flat struct (rather than a Rust enum with payload variants)
/// so that the Dart binding stays a plain `dart class`, no `freezed` dep.
#[derive(Debug, Clone)]
pub struct AppInboundEventC {
    pub kind: AppInboundKindC,
    pub from_peer_id: u32,
    pub channel: String,
    /// `request_id` echoed from the caller (0 for `Notify`).
    pub request_id: u64,
    /// Reply correlation token (0 for `Notify`). Pass to [`app_call_reply`].
    pub token: u64,
    pub payload: Vec<u8>,
}

fn lookup_app_rpc(
    instance_id: &str,
) -> Result<std::sync::Arc<app_rpc::AstralAppRpcService>, String> {
    let id = parse_instance_id(instance_id)?;
    app_rpc::get_service(&id)
        .ok_or_else(|| format!("astral app rpc service not found for instance {}", id))
}

/// 等 `astral_app_rpc::install` 完成。仅在真正要用 App RPC 的 API 上等待，
/// 不阻塞 [`create_instance`]（Astral2 等客户端不依赖 peer RPC）。
async fn lookup_app_rpc_ready(
    instance_id: &str,
    timeout: std::time::Duration,
) -> Result<std::sync::Arc<app_rpc::AstralAppRpcService>, String> {
    let step = std::time::Duration::from_millis(50);
    let deadline = std::time::Instant::now() + timeout;
    loop {
        match lookup_app_rpc(instance_id) {
            Ok(svc) => return Ok(svc),
            Err(err) => {
                if std::time::Instant::now() >= deadline {
                    return Err(err);
                }
                tokio::time::sleep(step).await;
            }
        }
    }
}

/// Send a request-response RPC to `dst_peer_id` and await the typed reply.
///
/// 不要用 `RT.spawn(...).await` 把这次调用搬到 `RT` —— `RT` 既不是 FRB 的
/// runtime，也不是 EasyTier 每个 instance 自己的 runtime（见 `EasyTierLauncher::start`
/// 里的 `std::thread::spawn` + 独立 `tokio::runtime::Runtime`）。跨三个 runtime
/// 调度时，`tokio::time::timeout` 注册在 RT 的 timer driver、mpsc 唤醒发生在
/// EasyTier runtime、JoinHandle 唤醒落在 FRB executor，时序上很容易错过 wake，
/// 表现为 Dart 侧 `appCall` 永久 Pending、5s 超时也不触发。直接在 FRB executor
/// 上 `.await svc.call()` 反而是稳的（参考 commit a0fb25e）。
pub async fn app_call(
    instance_id: String,
    dst_peer_id: u32,
    channel: String,
    request_id: u64,
    payload: Vec<u8>,
    flags: u32,
    timeout_ms: i32,
) -> Result<AppCallResultC, String> {
    let svc = lookup_app_rpc_ready(&instance_id, std::time::Duration::from_secs(5)).await?;
    let resp = svc
        .call(dst_peer_id, channel, request_id, payload, flags, timeout_ms)
        .await
        .map_err(|e| e.to_string())?;
    Ok(AppCallResultC {
        status: resp.status,
        error_msg: resp.error_msg,
        payload: resp.payload,
    })
}

/// Send a fire-and-forget notification to `dst_peer_id`. The RPC ack is still
/// awaited so the caller can detect routing failures within `timeout_ms`.
pub async fn app_notify(
    instance_id: String,
    dst_peer_id: u32,
    channel: String,
    payload: Vec<u8>,
    timeout_ms: i32,
) -> Result<(), String> {
    let svc = lookup_app_rpc_ready(&instance_id, std::time::Duration::from_secs(5)).await?;
    svc.notify(dst_peer_id, channel, payload, timeout_ms)
        .await
        .map_err(|e| e.to_string())
}

/// Round-trip ping. Returns the measured RTT in milliseconds.
pub async fn peer_ping(
    instance_id: String,
    dst_peer_id: u32,
    timeout_ms: i32,
) -> Result<i64, String> {
    let svc = lookup_app_rpc_ready(&instance_id, std::time::Duration::from_secs(5)).await?;
    svc.ping(dst_peer_id, timeout_ms)
        .await
        .map_err(|e| e.to_string())
}

/// Stream inbound `Call` and `Notify` events from a running instance into
/// Dart. The future resolves once the EasyTier instance shuts down (the
/// underlying broadcast channel is closed); Dart can re-subscribe after a
/// subsequent `create_instance` call.
pub async fn subscribe_app_inbound(
    instance_id: String,
    sink: StreamSink<AppInboundEventC>,
) -> Result<(), String> {
    let svc = lookup_app_rpc_ready(&instance_id, std::time::Duration::from_secs(15)).await?;
    let mut rx = svc.subscribe_inbound();
    drop(svc);
    loop {
        match rx.recv().await {
            Ok(evt) => {
                let mapped = match evt {
                    app_rpc::AppInboundEvent::Call {
                        from_peer_id,
                        channel,
                        request_id,
                        token,
                        payload,
                    } => AppInboundEventC {
                        kind: AppInboundKindC::Call,
                        from_peer_id,
                        channel,
                        request_id,
                        token,
                        payload,
                    },
                    app_rpc::AppInboundEvent::Notify {
                        from_peer_id,
                        channel,
                        payload,
                    } => AppInboundEventC {
                        kind: AppInboundKindC::Notify,
                        from_peer_id,
                        channel,
                        request_id: 0,
                        token: 0,
                        payload,
                    },
                };
                if sink.add(mapped).is_err() {
                    // Dart cancelled the stream.
                    break;
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                tracing_log_lagged(&instance_id, skipped);
                // Slow consumer; continue draining.
                continue;
            }
        }
    }
    Ok(())
}

/// Reply to an inbound `Call` identified by `token`. Returns `true` if the
/// reply was delivered to the awaiting RPC task, `false` if the token was
/// already replied to / timed out / never existed.
///
/// `status == 0` is convention for "ok"; positive values are application
/// defined; negative values are reserved for transport-level codes (see
/// [`app_rpc_status`]).
pub async fn app_call_reply(
    instance_id: String,
    token: u64,
    status: i32,
    error_msg: String,
    payload: Vec<u8>,
) -> Result<bool, String> {
    let svc = lookup_app_rpc(&instance_id)?;
    Ok(svc.reply_call(token, status, error_msg, payload))
}

/// Local peer id for the given instance, exposed so Dart can label outgoing
/// traffic (the EasyTier route table uses the same `peer_id` space).
pub async fn my_peer_id(instance_id: String) -> Result<u32, String> {
    let svc = lookup_app_rpc_ready(&instance_id, std::time::Duration::from_secs(15)).await?;
    Ok(svc.my_peer_id())
}

fn tracing_log_lagged(instance_id: &str, skipped: u64) {
    // We don't pull `tracing` into AstralNext; just write to stderr at debug
    // verbosity since this is a slow-consumer signal and not a hard error.
    eprintln!(
        "[astral_app_rpc] inbound stream lagged for instance {} (skipped {} events)",
        instance_id, skipped
    );
}

// ============================================================================
// Credential management
//
// v2.7 凭据操作已是 `CoreInstance` 的原生方法（内部走本地
// CredentialManager，并检查调用方持有 network_secret），不再需要旧版
// `InstanceRpcService` / `CredentialManageRpc` 套壳。
// ============================================================================

use std::time::Duration;

use easytier::instance::factory::NativeCoreInstance;
use easytier::peers::credential_manager::CredentialCreateOptions;

/// 房主生成的进网凭据（客人用 `credential_secret` 作为 secure_mode.local_private_key）。
#[derive(Debug, Clone)]
pub struct GeneratedCredentialC {
    pub credential_id: String,
    pub credential_secret: String,
    /// 与 EasyTier CredentialEntry.pubkey 一致（base64），用于踢人时匹配 peer。
    pub pubkey_b64: String,
}

#[derive(Debug, Clone)]
pub struct CredentialInfoC {
    pub credential_id: String,
    pub groups: Vec<String>,
    pub allow_relay: bool,
    pub expiry_unix: i64,
    pub reusable: bool,
}

fn pubkey_b64_from_credential_secret(secret_b64: &str) -> Result<String, String> {
    use base64::Engine;
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(secret_b64.trim())
        .map_err(|e| format!("invalid credential_secret base64: {}", e))?;
    let arr: [u8; 32] = bytes
        .as_slice()
        .try_into()
        .map_err(|_| "credential_secret must be 32 bytes".to_string())?;
    let private = x25519_dalek::StaticSecret::from(arr);
    let public = x25519_dalek::PublicKey::from(&private);
    Ok(base64::engine::general_purpose::STANDARD.encode(public.as_bytes()))
}

async fn lookup_native_instance(
    instance_id: &str,
    timeout: Duration,
) -> Result<std::sync::Arc<NativeCoreInstance>, String> {
    let id = parse_instance_id(instance_id)?;
    let step = Duration::from_millis(50);
    let deadline = std::time::Instant::now() + timeout;
    loop {
        if let Some(instance) = MANAGER.instance(id) {
            return Ok(instance);
        }
        if std::time::Instant::now() >= deadline {
            return Err(format!("instance not ready: {}", instance_id));
        }
        tokio::time::sleep(step).await;
    }
}

/// 管理节点（持有 network_secret）生成进网凭据。
///
/// `ttl_seconds` 必须 > 0。`reusable=false` 时一人一凭（适合短码邀请）。
pub async fn generate_credential(
    instance_id: String,
    ttl_seconds: i64,
    reusable: bool,
) -> Result<GeneratedCredentialC, String> {
    if ttl_seconds <= 0 {
        return Err("ttl_seconds must be positive".to_string());
    }
    let instance = lookup_native_instance(&instance_id, Duration::from_secs(5)).await?;
    let resp = instance
        .generate_credential(CredentialCreateOptions {
            groups: vec![],
            // 客人经公共服务器进房时需要参与中继路由；false 时易出现连上中继马上断开、无 DHCP。
            allow_relay: true,
            allowed_proxy_cidrs: vec![],
            ttl: Duration::from_secs(ttl_seconds as u64),
            credential_id: None,
            reusable,
        })
        .map_err(|e| e.to_string())?;
    let pubkey_b64 = pubkey_b64_from_credential_secret(&resp.secret)?;
    Ok(GeneratedCredentialC {
        credential_id: resp.credential_id,
        credential_secret: resp.secret,
        pubkey_b64,
    })
}

/// 撤销凭据；成功后对端将被踢出（不再受信任）。
pub async fn revoke_credential(instance_id: String, credential_id: String) -> Result<bool, String> {
    let instance = lookup_native_instance(&instance_id, Duration::from_secs(5)).await?;
    instance
        .revoke_credential(&credential_id)
        .map_err(|e| e.to_string())
}

/// 列出当前实例上仍有效的凭据。
pub async fn list_credentials(instance_id: String) -> Result<Vec<CredentialInfoC>, String> {
    let instance = lookup_native_instance(&instance_id, Duration::from_secs(5)).await?;
    Ok(instance
        .credential_snapshots()
        .into_iter()
        .map(|c| CredentialInfoC {
            credential_id: c.credential_id,
            groups: c.groups,
            allow_relay: c.allow_relay,
            expiry_unix: c.expiry_unix,
            reusable: c.reusable.unwrap_or(true),
        })
        .collect())
}
