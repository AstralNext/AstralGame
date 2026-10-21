//! 局域网地址映射（LAN NAT）。
//!
//! 一些老游戏的「局域网联机」只接受与本机物理网段相同的房主地址：它们能看到
//! 虚拟网里广播出来的房间，但点加入时不会向虚拟网地址发包。这里把房主的虚拟
//! IP 映射成玩家物理网段里的一个假地址：
//!
//! - 入向（peer -> tun）：把来自房主的包源地址改成假地址，游戏就认为房主在本机网段；
//! - 出向（tun -> peer）：把游戏发往假地址的包目标地址改回房主虚拟 IP。
//!
//! 房主地址不需要提前配置：从配置端口上的第一个入向包学习。IPv4 + UDP，
//! 分片按 IP 头里的分片偏移逐片改写，首片把 UDP 校验和置 0（IPv4 允许）。

use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, RwLock};

use easytier::peers::{NicPacketFilter, PeerPacketFilter, PeerPacketFilterResult};
use easytier_core::packet::ZCPacket;
use lazy_static::lazy_static;

const IPPROTO_UDP: u8 = 17;

/// 单个实例的映射状态。过滤器持有它的 Arc，改规则时原地更新。
pub struct NatState {
    enabled: AtomicBool,
    fake: AtomicU32,
    target: AtomicU32,
    ports: RwLock<Vec<u16>>,
}

impl NatState {
    fn new(fake: Ipv4Addr, ports: Vec<u16>) -> Self {
        Self {
            enabled: AtomicBool::new(true),
            fake: AtomicU32::new(u32::from(fake)),
            target: AtomicU32::new(0),
            ports: RwLock::new(ports),
        }
    }

    fn fake(&self) -> Ipv4Addr {
        Ipv4Addr::from(self.fake.load(Ordering::Relaxed))
    }

    fn target(&self) -> Option<Ipv4Addr> {
        let v = self.target.load(Ordering::Relaxed);
        (v != 0).then(|| Ipv4Addr::from(v))
    }

    fn port_matches(&self, port: u16) -> bool {
        self.ports
            .read()
            .map(|p| p.contains(&port))
            .unwrap_or(false)
    }
}

lazy_static! {
    static ref STATES: Mutex<HashMap<String, Arc<NatState>>> = Mutex::new(HashMap::new());
}

/// 注册（或更新）某实例的映射。返回 `true` 表示需要挂过滤器。
pub fn register(instance_id: &str, fake: Ipv4Addr, ports: Vec<u16>) -> (Arc<NatState>, bool) {
    let mut map = STATES.lock().unwrap();
    if let Some(state) = map.get(instance_id) {
        state.fake.store(u32::from(fake), Ordering::Relaxed);
        state.target.store(0, Ordering::Relaxed);
        if let Ok(mut p) = state.ports.write() {
            *p = ports;
        }
        state.enabled.store(true, Ordering::Relaxed);
        return (state.clone(), false);
    }
    let state = Arc::new(NatState::new(fake, ports));
    map.insert(instance_id.to_string(), state.clone());
    (state, true)
}

/// 停用映射；实例销毁时调用。
pub fn unregister(instance_id: &str) {
    if let Some(state) = STATES.lock().unwrap().remove(instance_id) {
        state.enabled.store(false, Ordering::Relaxed);
    }
}

pub struct NicNatFilter {
    state: Arc<NatState>,
}

impl NicNatFilter {
    pub fn new(state: Arc<NatState>) -> Self {
        Self { state }
    }
}

#[async_trait::async_trait]
impl NicPacketFilter for NicNatFilter {
    async fn try_process_packet_from_nic(&self, data: &mut ZCPacket) -> bool {
        if self.state.enabled.load(Ordering::Relaxed) {
            rewrite_outbound(data.mut_payload(), &self.state);
        }
        true
    }

    fn id(&self) -> String {
        "lan_nat_out".to_string()
    }
}

pub struct PeerNatFilter {
    state: Arc<NatState>,
}

impl PeerNatFilter {
    pub fn new(state: Arc<NatState>) -> Self {
        Self { state }
    }
}

#[async_trait::async_trait]
impl PeerPacketFilter for PeerNatFilter {
    async fn try_process_packet_from_peer(&self, mut packet: ZCPacket) -> PeerPacketFilterResult {
        if self.state.enabled.load(Ordering::Relaxed) {
            rewrite_inbound(packet.mut_payload(), &self.state);
        }
        PeerPacketFilterResult::Pass(packet)
    }
}

struct Ipv4View {
    ihl: usize,
    proto: u8,
    frag_offset: u16,
    total_len: usize,
    src: Ipv4Addr,
    dst: Ipv4Addr,
    src_port: Option<u16>,
    dst_port: Option<u16>,
}

fn parse_ipv4(buf: &[u8]) -> Option<Ipv4View> {
    if buf.len() < 20 || buf[0] >> 4 != 4 {
        return None;
    }
    let ihl = ((buf[0] & 0x0f) as usize) * 4;
    if ihl < 20 || buf.len() < ihl {
        return None;
    }
    let total_len = u16::from_be_bytes([buf[2], buf[3]]) as usize;
    if total_len < ihl || total_len > buf.len() {
        return None;
    }
    let frag = u16::from_be_bytes([buf[6], buf[7]]);
    let frag_offset = frag & 0x1fff;
    let proto = buf[9];
    let src = Ipv4Addr::new(buf[12], buf[13], buf[14], buf[15]);
    let dst = Ipv4Addr::new(buf[16], buf[17], buf[18], buf[19]);

    let (src_port, dst_port) = if frag_offset == 0
        && matches!(proto, IPPROTO_UDP)
        && total_len >= ihl + 4
    {
        (
            Some(u16::from_be_bytes([buf[ihl], buf[ihl + 1]])),
            Some(u16::from_be_bytes([buf[ihl + 2], buf[ihl + 3]])),
        )
    } else {
        (None, None)
    };

    Some(Ipv4View {
        ihl,
        proto,
        frag_offset,
        total_len,
        src,
        dst,
        src_port,
        dst_port,
    })
}

/// 游戏 -> 虚拟网：目标假地址改回房主虚拟 IP。
fn rewrite_outbound(buf: &mut [u8], state: &NatState) -> bool {
    let Some(view) = parse_ipv4(buf) else {
        return false;
    };
    if view.proto != IPPROTO_UDP || view.dst != state.fake() {
        return false;
    }
    tracing::trace!(dst = %view.dst, target = ?state.target(), "lan_nat outbound hit");
    let Some(target) = state.target() else {
        // 还没学到房主地址：丢掉比放出去更安全，避免泄漏到物理局域网。
        return false;
    };

    let bytes = target.octets();
    buf[16..20].copy_from_slice(&bytes);
    fix_ip_checksum(buf, view.ihl);
    // 分片首片含 UDP 头，源地址变化后校验和失效；IPv4 允许置 0 表示不校验。
    if view.frag_offset == 0 && view.total_len >= view.ihl + 8 {
        buf[view.ihl + 6] = 0;
        buf[view.ihl + 7] = 0;
    }
    true
}

/// 虚拟网 -> 游戏：房主虚拟 IP 改成假地址，并学习房主地址。
fn rewrite_inbound(buf: &mut [u8], state: &NatState) -> bool {
    let Some(view) = parse_ipv4(buf) else {
        return false;
    };
    if view.proto != IPPROTO_UDP {
        return false;
    }

    if state.target().is_none() {
        let from_service = view.src_port.is_some_and(|p| state.port_matches(p))
            || view.dst_port.is_some_and(|p| state.port_matches(p));
        if from_service && !view.src.is_unspecified() {
            state
                .target
                .store(u32::from(view.src), Ordering::Relaxed);
            tracing::debug!(host = %view.src, "lan_nat learned host");
        }
    }

    if state.target() != Some(view.src) {
        return false;
    }

    let bytes = state.fake().octets();
    buf[12..16].copy_from_slice(&bytes);
    fix_ip_checksum(buf, view.ihl);
    if view.frag_offset == 0 && view.total_len >= view.ihl + 8 {
        buf[view.ihl + 6] = 0;
        buf[view.ihl + 7] = 0;
    }
    true
}

fn fix_ip_checksum(buf: &mut [u8], ihl: usize) {
    buf[10] = 0;
    buf[11] = 0;
    let mut sum: u32 = 0;
    let mut i = 0;
    while i + 1 < ihl {
        sum += u16::from_be_bytes([buf[i], buf[i + 1]]) as u32;
        i += 2;
    }
    while sum >> 16 != 0 {
        sum = (sum & 0xffff) + (sum >> 16);
    }
    let checksum = !(sum as u16);
    let bytes = checksum.to_be_bytes();
    buf[10] = bytes[0];
    buf[11] = bytes[1];
}

#[cfg(test)]
mod tests {
    use super::*;

    fn build_udp(
        src: Ipv4Addr,
        dst: Ipv4Addr,
        sport: u16,
        dport: u16,
        payload: &[u8],
    ) -> Vec<u8> {
        let total = 20 + 8 + payload.len();
        let mut p = vec![0u8; total];
        p[0] = 0x45;
        p[2..4].copy_from_slice(&(total as u16).to_be_bytes());
        p[8] = 64;
        p[9] = IPPROTO_UDP;
        p[12..16].copy_from_slice(&src.octets());
        p[16..20].copy_from_slice(&dst.octets());
        p[20..22].copy_from_slice(&sport.to_be_bytes());
        p[22..24].copy_from_slice(&dport.to_be_bytes());
        p[24..26].copy_from_slice(&((8 + payload.len()) as u16).to_be_bytes());
        p[28..].copy_from_slice(payload);
        fix_ip_checksum(&mut p, 20);
        p
    }

    fn checksum_ok(packet: &[u8], ihl: usize) -> bool {
        let mut sum: u32 = 0;
        let mut i = 0;
        while i + 1 < ihl {
            sum += u16::from_be_bytes([packet[i], packet[i + 1]]) as u32;
            i += 2;
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xffff) + (sum >> 16);
        }
        sum as u16 == 0xffff
    }

    #[test]
    fn inbound_learns_host_and_rewrites_source() {
        let fake = Ipv4Addr::new(192, 168, 31, 250);
        let host = Ipv4Addr::new(100, 100, 100, 2);
        let me = Ipv4Addr::new(100, 100, 100, 1);
        let state = NatState::new(fake, vec![62900, 62056]);

        let mut pkt = build_udp(host, me, 62900, 40000, b"room");
        assert!(checksum_ok(&pkt, 20));
        assert!(rewrite_inbound(&mut pkt, &state));
        assert_eq!(Ipv4Addr::new(pkt[12], pkt[13], pkt[14], pkt[15]), fake);
        assert_eq!(state.target(), Some(host));
        assert!(checksum_ok(&pkt, 20));
        assert_eq!(&pkt[26..28], &[0, 0], "UDP checksum should be zeroed");
    }

    #[test]
    fn outbound_rewrites_destination_to_learned_host() {
        let fake = Ipv4Addr::new(192, 168, 31, 250);
        let host = Ipv4Addr::new(100, 100, 100, 2);
        let me = Ipv4Addr::new(100, 100, 100, 1);
        let state = NatState::new(fake, vec![62900, 62056]);

        let mut learn = build_udp(host, me, 62900, 40000, b"room");
        assert!(rewrite_inbound(&mut learn, &state));

        let mut join = build_udp(me, fake, 62056, 62056, b"join");
        assert!(rewrite_outbound(&mut join, &state));
        assert_eq!(Ipv4Addr::new(join[16], join[17], join[18], join[19]), host);
        assert!(checksum_ok(&join, 20));
        assert_eq!(&join[26..28], &[0, 0]);
    }

    #[test]
    fn outbound_without_known_host_is_left_alone() {
        let fake = Ipv4Addr::new(192, 168, 31, 250);
        let me = Ipv4Addr::new(100, 100, 100, 1);
        let state = NatState::new(fake, vec![62056]);
        let mut pkt = build_udp(me, fake, 62056, 62056, b"join");
        let before = pkt.clone();
        assert!(!rewrite_outbound(&mut pkt, &state));
        assert_eq!(pkt, before);
    }

    #[test]
    fn unrelated_traffic_is_untouched() {
        let fake = Ipv4Addr::new(192, 168, 31, 250);
        let host = Ipv4Addr::new(100, 100, 100, 2);
        let me = Ipv4Addr::new(100, 100, 100, 1);
        let state = NatState::new(fake, vec![62900]);
        // 端口不匹配的入向包不触发学习
        let mut pkt = build_udp(host, me, 443, 40000, b"https");
        assert!(!rewrite_inbound(&mut pkt, &state));
        assert_eq!(state.target(), None);
        assert_eq!(Ipv4Addr::new(pkt[12], pkt[13], pkt[14], pkt[15]), host);
    }

    #[test]
    fn fragmented_tail_is_still_rewritten() {
        let fake = Ipv4Addr::new(192, 168, 31, 250);
        let host = Ipv4Addr::new(100, 100, 100, 2);
        let me = Ipv4Addr::new(100, 100, 100, 1);
        let state = NatState::new(fake, vec![62900]);

        let mut head = build_udp(host, me, 62900, 40000, b"first");
        assert!(rewrite_inbound(&mut head, &state));

        // 非首片：没有 UDP 头，只改 IP 源地址
        let mut tail = vec![0u8; 40];
        tail[0] = 0x45;
        tail[2..4].copy_from_slice(&40u16.to_be_bytes());
        tail[6..8].copy_from_slice(&(0x2000u16 | 5).to_be_bytes()); // MF + offset 5
        tail[8] = 64;
        tail[9] = IPPROTO_UDP;
        tail[12..16].copy_from_slice(&host.octets());
        tail[16..20].copy_from_slice(&me.octets());
        fix_ip_checksum(&mut tail, 20);
        assert!(rewrite_inbound(&mut tail, &state));
        assert_eq!(Ipv4Addr::new(tail[12], tail[13], tail[14], tail[15]), fake);
        assert!(checksum_ok(&tail, 20));
    }
}

/// 在玩家物理网段里挑一个假地址（默认 .250），供 VpnService 加 /32 路由。
///
/// 只认局域网网卡（Wi‑Fi / 以太网）：手机常同时有蜂窝网卡（rmnet/ccmni），
/// 选到运营商网段（如 100.64/10）时假地址不在游戏所在局域网里，等于没映射。
pub fn pick_fake_ip() -> Result<Ipv4Addr, String> {
    let ifas = local_ip_address::list_afinet_netifas()
        .map_err(|e| format!("enumerate interfaces failed: {e}"))?;
    let mut candidates = Vec::new();
    for (name, ip) in ifas {
        let IpAddr::V4(v4) = ip else { continue };
        if v4.is_loopback() || v4.is_link_local() || v4.is_unspecified() {
            continue;
        }
        let o = v4.octets();
        // 只要 RFC1918 私网；排除 100.64/10（运营商 CGNAT）与 100.100.100.x 虚拟网。
        let private = o[0] == 10
            || (o[0] == 172 && (16..=31).contains(&o[1]))
            || (o[0] == 192 && o[1] == 168);
        if !private {
            continue;
        }
        let lower = name.to_lowercase();
        let non_lan = ["tun", "rmnet", "ccmni", "pdp", "clat", "dummy", "ip6tnl", "sit", "p2p"];
        if non_lan.iter().any(|p| lower.starts_with(p))
            || lower.contains("vethernet")
            || lower.contains("docker")
        {
            continue;
        }
        let preferred = lower.starts_with("wlan")
            || lower.starts_with("wifi")
            || lower.starts_with("eth");
        candidates.push((preferred, v4));
    }
    candidates.sort_by_key(|(preferred, _)| !*preferred);
    for (_, v4) in candidates {
        let o = v4.octets();
        let last = if o[3] == 250 { 249 } else { 250 };
        return Ok(Ipv4Addr::new(o[0], o[1], o[2], last));
    }
    Err("no suitable LAN IPv4 address".to_string())
}
