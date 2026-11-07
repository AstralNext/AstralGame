//! Steam 组网的帧格式、控制消息与应用 RPC 编解码。
//!
//! 控制与数据共用一条 P2P 连接（虚拟端口 [`VPORT`]），靠帧头的 `kind` 区分。
//! 所有多字节字段一律小端；字符串为 UTF-8（u16 长度前缀）。

use std::net::Ipv4Addr;

/// 组网专用 P2P 虚拟端口（控制 + 数据 + RPC 共用）。
pub const VPORT: i32 = 0xA57A;
/// 帧版本。变更协议时递增；帧头版本不一致会被直接丢弃。
pub const VERSION: u8 = 1;

pub const KIND_IP: u8 = 0;
pub const KIND_CONTROL: u8 = 1;
pub const KIND_RPC: u8 = 3;

/// 泛洪给房间内除来源外的所有成员（广播 / 组播）。
pub const FLAG_FLOOD: u8 = 0x01;

pub const HEADER_LEN: usize = 12;
/// Steam 单条消息上限（SDR 建议 32KB 以内）。
pub const MAX_MESSAGE: usize = 32 * 1024;
/// 单 tick 聚合同一目标的最大字节数；超过就先 flush，留出帧头余量。
pub const MAX_BATCH_BYTES: usize = MAX_MESSAGE - HEADER_LEN;

pub const MTU: usize = 1280;
/// 沿用 EasyTier 的虚拟网段 100.100.100.0/24。
pub const PREFIX: [u8; 3] = [100, 100, 100];
pub const HOST_VIP: Ipv4Addr = Ipv4Addr::new(100, 100, 100, 1);
pub const BROADCAST_VIP: Ipv4Addr = Ipv4Addr::new(255, 255, 255, 255);

/// 控制消息类型。
pub const CTL_HELLO: u8 = 1;
pub const CTL_WELCOME: u8 = 2;
pub const CTL_ROSTER: u8 = 3;
pub const CTL_PING: u8 = 4;
pub const CTL_PONG: u8 = 5;
pub const CTL_BYE: u8 = 6;
pub const CTL_KICK: u8 = 7;

/// 应用 RPC 操作。
pub const RPC_CALL: u8 = 1;
pub const RPC_NOTIFY: u8 = 2;
pub const RPC_REPLY: u8 = 3;
pub const RPC_PING: u8 = 4;

pub struct Frame<'a> {
    pub kind: u8,
    pub flags: u8,
    pub src: Ipv4Addr,
    pub dst: Ipv4Addr,
    pub payload: &'a [u8],
}

pub fn encode(kind: u8, flags: u8, src: Ipv4Addr, dst: Ipv4Addr, payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(HEADER_LEN + payload.len());
    out.push(VERSION);
    out.push(kind);
    out.push(flags);
    out.push(0);
    out.extend_from_slice(&u32::from(src).to_le_bytes());
    out.extend_from_slice(&u32::from(dst).to_le_bytes());
    out.extend_from_slice(payload);
    out
}

pub fn decode(data: &[u8]) -> Option<Frame<'_>> {
    if data.len() < HEADER_LEN || data[0] != VERSION {
        return None;
    }
    let src = Ipv4Addr::from(u32::from_le_bytes([data[4], data[5], data[6], data[7]]));
    let dst = Ipv4Addr::from(u32::from_le_bytes([data[8], data[9], data[10], data[11]]));
    Some(Frame {
        kind: data[1],
        flags: data[2],
        src,
        dst,
        payload: &data[HEADER_LEN..],
    })
}

pub fn vip(host_octet: u8) -> Ipv4Addr {
    Ipv4Addr::new(PREFIX[0], PREFIX[1], PREFIX[2], host_octet)
}

pub fn is_room_vip(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    o[0] == PREFIX[0] && o[1] == PREFIX[1] && o[2] == PREFIX[2]
}

pub fn is_broadcast(ip: Ipv4Addr) -> bool {
    ip == BROADCAST_VIP || (is_room_vip(ip) && ip.octets()[3] == 255)
}

pub fn is_multicast(ip: Ipv4Addr) -> bool {
    ip.octets()[0] & 0xF0 == 0xE0
}

/// 把一条消息里拼接的 IPv4 包按头部 `total_length` 切开。
pub fn split_ipv4(payload: &[u8]) -> Vec<&[u8]> {
    let mut out = Vec::new();
    let mut off = 0usize;
    while off + 20 <= payload.len() {
        let ver = payload[off] >> 4;
        if ver != 4 {
            break;
        }
        let ihl = ((payload[off] & 0x0F) as usize) * 4;
        if ihl < 20 || off + ihl > payload.len() {
            break;
        }
        let total = u16::from_be_bytes([payload[off + 2], payload[off + 3]]) as usize;
        if total < ihl || off + total > payload.len() {
            break;
        }
        out.push(&payload[off..off + total]);
        off += total;
    }
    out
}

pub fn ipv4_dst(packet: &[u8]) -> Option<Ipv4Addr> {
    if packet.len() < 20 || packet[0] >> 4 != 4 {
        return None;
    }
    Some(Ipv4Addr::new(
        packet[16], packet[17], packet[18], packet[19],
    ))
}

// ---------------------------------------------------------------------------
// 字节读写
// ---------------------------------------------------------------------------

pub struct Writer {
    buf: Vec<u8>,
}

impl Writer {
    pub fn new() -> Self {
        Self { buf: Vec::new() }
    }

    pub fn u8(&mut self, v: u8) {
        self.buf.push(v);
    }
    pub fn u16(&mut self, v: u16) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
    pub fn u32(&mut self, v: u32) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
    pub fn u64(&mut self, v: u64) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
    pub fn i32(&mut self, v: i32) {
        self.buf.extend_from_slice(&v.to_le_bytes());
    }
    pub fn str(&mut self, s: &str) {
        let bytes = s.as_bytes();
        let len = bytes.len().min(u16::MAX as usize);
        self.u16(len as u16);
        self.buf.extend_from_slice(&bytes[..len]);
    }
    pub fn bytes(&mut self, b: &[u8]) {
        self.u32(b.len() as u32);
        self.buf.extend_from_slice(b);
    }
    pub fn finish(self) -> Vec<u8> {
        self.buf
    }
}

pub struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }

    pub fn u8(&mut self) -> Option<u8> {
        let v = *self.data.get(self.pos)?;
        self.pos += 1;
        Some(v)
    }
    pub fn u16(&mut self) -> Option<u16> {
        let end = self.pos.checked_add(2)?;
        let bytes = self.data.get(self.pos..end)?;
        self.pos = end;
        Some(u16::from_le_bytes([bytes[0], bytes[1]]))
    }
    pub fn u32(&mut self) -> Option<u32> {
        let end = self.pos.checked_add(4)?;
        let bytes = self.data.get(self.pos..end)?;
        self.pos = end;
        Some(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }
    pub fn u64(&mut self) -> Option<u64> {
        let end = self.pos.checked_add(8)?;
        let bytes = self.data.get(self.pos..end)?;
        self.pos = end;
        Some(u64::from_le_bytes([
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        ]))
    }
    pub fn i32(&mut self) -> Option<i32> {
        self.u32().map(|v| v as i32)
    }
    pub fn str(&mut self) -> Option<String> {
        let len = self.u16()? as usize;
        let end = self.pos.checked_add(len)?;
        let bytes = self.data.get(self.pos..end)?;
        self.pos = end;
        Some(String::from_utf8_lossy(bytes).into_owned())
    }
    pub fn bytes(&mut self) -> Option<Vec<u8>> {
        let len = self.u32()? as usize;
        let end = self.pos.checked_add(len)?;
        let bytes = self.data.get(self.pos..end)?;
        self.pos = end;
        Some(bytes.to_vec())
    }
}

// ---------------------------------------------------------------------------
// 控制消息
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct HelloMsg {
    pub token: String,
    pub steam_id: u64,
    pub nickname: String,
    pub version: String,
    /// 大厅 `ag_game` 的游戏标识，由房主二次校验。
    pub game_id: String,
}

#[derive(Clone, Debug)]
pub struct WelcomeMsg {
    pub vip: Ipv4Addr,
    pub host_vip: Ipv4Addr,
    pub peer_id: u32,
    pub network: String,
    pub mtu: u16,
}

impl Default for WelcomeMsg {
    fn default() -> Self {
        Self {
            vip: Ipv4Addr::UNSPECIFIED,
            host_vip: Ipv4Addr::UNSPECIFIED,
            peer_id: 0,
            network: String::new(),
            mtu: 0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct RosterEntry {
    pub peer_id: u32,
    pub steam_id: u64,
    pub nickname: String,
    pub vip: Ipv4Addr,
    pub online: bool,
    pub is_host: bool,
    pub latency_ms: u32,
    /// Steam 连接是否经中继转发（false = 直连）。
    pub via_relay: bool,
    /// 该成员自上次上线以来累计接收字节（房主实测，客机只读）。
    pub bytes_in: u64,
    /// 该成员累计发送字节。
    pub bytes_out: u64,
}

pub fn hello(msg: &HelloMsg) -> Vec<u8> {
    let mut w = Writer::new();
    w.u8(CTL_HELLO);
    w.str(&msg.token);
    w.u64(msg.steam_id);
    w.str(&msg.nickname);
    w.str(&msg.version);
    w.str(&msg.game_id);
    w.finish()
}

pub fn welcome(msg: &WelcomeMsg) -> Vec<u8> {
    let mut w = Writer::new();
    w.u8(CTL_WELCOME);
    w.u32(u32::from(msg.vip));
    w.u32(u32::from(msg.host_vip));
    w.u32(msg.peer_id);
    w.str(&msg.network);
    w.u16(msg.mtu);
    w.finish()
}

pub fn roster(entries: &[RosterEntry]) -> Vec<u8> {
    let mut w = Writer::new();
    w.u8(CTL_ROSTER);
    w.u32(entries.len() as u32);
    for e in entries {
        w.u32(e.peer_id);
        w.u64(e.steam_id);
        w.str(&e.nickname);
        w.u32(u32::from(e.vip));
        // 状态标志：bit0 = 在线，bit1 = 走 Steam 中继。
        w.u8(u8::from(e.online) | (u8::from(e.via_relay) << 1));
        w.u8(if e.is_host { 1 } else { 0 });
        w.u16(e.latency_ms.min(u16::MAX as u32) as u16);
        w.u64(e.bytes_in);
        w.u64(e.bytes_out);
    }
    w.finish()
}

pub fn simple_control(kind: u8) -> Vec<u8> {
    vec![kind]
}

pub fn kick(reason: &str) -> Vec<u8> {
    let mut w = Writer::new();
    w.u8(CTL_KICK);
    w.str(reason);
    w.finish()
}

pub fn parse_hello(data: &[u8]) -> Option<HelloMsg> {
    let mut r = Reader::new(data);
    if r.u8()? != CTL_HELLO {
        return None;
    }
    Some(HelloMsg {
        token: r.str()?,
        steam_id: r.u64()?,
        nickname: r.str()?,
        version: r.str()?,
        game_id: r.str()?,
    })
}

pub fn parse_welcome(data: &[u8]) -> Option<WelcomeMsg> {
    let mut r = Reader::new(data);
    if r.u8()? != CTL_WELCOME {
        return None;
    }
    Some(WelcomeMsg {
        vip: Ipv4Addr::from(r.u32()?),
        host_vip: Ipv4Addr::from(r.u32()?),
        peer_id: r.u32()?,
        network: r.str()?,
        mtu: r.u16()?,
    })
}

pub fn parse_roster(data: &[u8]) -> Option<Vec<RosterEntry>> {
    let mut r = Reader::new(data);
    if r.u8()? != CTL_ROSTER {
        return None;
    }
    let count = r.u32()? as usize;
    let mut out = Vec::with_capacity(count.min(64));
    for _ in 0..count {
        let peer_id = r.u32()?;
        let steam_id = r.u64()?;
        let nickname = r.str()?;
        let vip = Ipv4Addr::from(r.u32()?);
        let flags = r.u8()?;
        out.push(RosterEntry {
            peer_id,
            steam_id,
            nickname,
            vip,
            online: flags & 1 != 0,
            is_host: r.u8()? != 0,
            latency_ms: r.u16()? as u32,
            via_relay: flags & 2 != 0,
            bytes_in: r.u64()?,
            bytes_out: r.u64()?,
        });
    }
    Some(out)
}

pub fn control_kind(data: &[u8]) -> Option<u8> {
    data.first().copied()
}

pub fn kick_reason(data: &[u8]) -> String {
    let mut r = Reader::new(data);
    if r.u8() != Some(CTL_KICK) {
        return String::new();
    }
    r.str().unwrap_or_default()
}

// ---------------------------------------------------------------------------
// 应用 RPC
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct RpcCall {
    pub request_id: u64,
    pub flags: u32,
    pub channel: String,
    pub payload: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct RpcReply {
    pub request_id: u64,
    pub status: i32,
    pub error_msg: String,
    pub payload: Vec<u8>,
}

pub fn rpc_call(op: u8, call: &RpcCall) -> Vec<u8> {
    let mut w = Writer::new();
    w.u8(op);
    w.u64(call.request_id);
    w.u32(call.flags);
    w.str(&call.channel);
    w.bytes(&call.payload);
    w.finish()
}

pub fn rpc_reply(reply: &RpcReply) -> Vec<u8> {
    let mut w = Writer::new();
    w.u8(RPC_REPLY);
    w.u64(reply.request_id);
    w.i32(reply.status);
    w.str(&reply.error_msg);
    w.bytes(&reply.payload);
    w.finish()
}

pub fn rpc_ping(request_id: u64) -> Vec<u8> {
    let mut w = Writer::new();
    w.u8(RPC_PING);
    w.u64(request_id);
    w.finish()
}

pub fn parse_rpc_call(data: &[u8]) -> Option<(u8, RpcCall)> {
    let mut r = Reader::new(data);
    let op = r.u8()?;
    Some((
        op,
        RpcCall {
            request_id: r.u64()?,
            flags: r.u32()?,
            channel: r.str()?,
            payload: r.bytes()?,
        },
    ))
}

pub fn parse_rpc_reply(data: &[u8]) -> Option<RpcReply> {
    let mut r = Reader::new(data);
    if r.u8()? != RPC_REPLY {
        return None;
    }
    Some(RpcReply {
        request_id: r.u64()?,
        status: r.i32()?,
        error_msg: r.str()?,
        payload: r.bytes()?,
    })
}

pub fn parse_rpc_ping(data: &[u8]) -> Option<u64> {
    let mut r = Reader::new(data);
    if r.u8()? != RPC_PING {
        return None;
    }
    r.u64()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn host_vip() -> Ipv4Addr {
        Ipv4Addr::new(100, 100, 100, 1)
    }

    fn peer_vip() -> Ipv4Addr {
        Ipv4Addr::new(100, 100, 100, 2)
    }

    #[test]
    fn frame_roundtrip_preserves_header_and_payload() {
        let payload = b"hello";
        let bytes = encode(KIND_IP, FLAG_FLOOD, peer_vip(), host_vip(), payload);
        assert_eq!(bytes.len(), HEADER_LEN + payload.len());

        let frame = decode(&bytes).expect("正常帧应能解出");
        assert_eq!(frame.kind, KIND_IP);
        assert_eq!(frame.flags, FLAG_FLOOD);
        assert_eq!(frame.src, peer_vip());
        assert_eq!(frame.dst, host_vip());
        assert_eq!(frame.payload, payload);
    }

    #[test]
    fn frame_with_empty_payload_is_valid_boundary() {
        let bytes = encode(KIND_CONTROL, 0, host_vip(), BROADCAST_VIP, &[]);
        assert_eq!(bytes.len(), HEADER_LEN);

        let frame = decode(&bytes).expect("只有帧头也应能解出");
        assert!(frame.payload.is_empty());
        assert_eq!(frame.dst, BROADCAST_VIP);
    }

    #[test]
    fn frame_with_max_batch_payload_roundtrips() {
        let payload = vec![0xAB; MAX_BATCH_BYTES];
        let bytes = encode(KIND_IP, 0, peer_vip(), host_vip(), &payload);
        assert_eq!(bytes.len(), MAX_MESSAGE);

        let frame = decode(&bytes).expect("上限长度帧应能解出");
        assert_eq!(frame.payload.len(), MAX_BATCH_BYTES);
        assert_eq!(frame.payload, payload.as_slice());
    }

    #[test]
    fn decode_rejects_short_input_and_version_mismatch() {
        assert!(decode(&[]).is_none());
        assert!(decode(&[VERSION; HEADER_LEN - 1]).is_none());

        let mut bad_version = encode(KIND_IP, 0, peer_vip(), host_vip(), b"x");
        bad_version[0] = VERSION.wrapping_add(1);
        assert!(decode(&bad_version).is_none());
    }

    #[test]
    fn decode_never_panics_on_malformed_input() {
        // 任意长度 / 内容的输入都只应返回 None 或原样透出，不得 panic。
        for len in 0..HEADER_LEN + 8 {
            let _ = decode(&vec![0x5A; len]);
        }

        // 帧头合法但 kind 未知：保留原始 kind，由上层忽略。
        let data = [VERSION, 0xFF, 0xFF, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
        let frame = decode(&data).expect("帧头合法即可解出");
        assert_eq!(frame.kind, 0xFF);
    }

    #[test]
    fn roster_roundtrip_preserves_flags_latency_and_counters() {
        let entries = vec![
            RosterEntry {
                peer_id: 1,
                steam_id: 42,
                nickname: "房主".to_string(),
                vip: host_vip(),
                online: true,
                is_host: true,
                latency_ms: 12,
                via_relay: false,
                bytes_in: 100,
                bytes_out: 200,
            },
            RosterEntry {
                peer_id: 2,
                steam_id: 7,
                nickname: "成员".to_string(),
                vip: peer_vip(),
                online: false,
                is_host: false,
                // 超过 u16 上限：编码时按 u16::MAX 截断。
                latency_ms: u32::MAX,
                via_relay: true,
                bytes_in: 1 << 40,
                bytes_out: 1 << 41,
            },
        ];

        let parsed = parse_roster(&roster(&entries)).expect("正常 Roster 应能解出");
        assert_eq!(parsed.len(), 2);

        let host = &parsed[0];
        assert_eq!(host.peer_id, 1);
        assert_eq!(host.steam_id, 42);
        assert_eq!(host.nickname, "房主");
        assert_eq!(host.vip, host_vip());
        assert!(host.online);
        assert!(host.is_host);
        assert!(!host.via_relay);
        assert_eq!(host.latency_ms, 12);
        assert_eq!(host.bytes_in, 100);
        assert_eq!(host.bytes_out, 200);

        let member = &parsed[1];
        assert!(!member.online);
        assert!(!member.is_host);
        assert!(member.via_relay);
        assert_eq!(member.latency_ms, u16::MAX as u32);
        assert_eq!(member.bytes_in, 1 << 40);
        assert_eq!(member.bytes_out, 1 << 41);
    }

    #[test]
    fn roster_with_no_entries_is_valid_boundary() {
        let parsed = parse_roster(&roster(&[])).expect("空成员表是合法边界");
        assert!(parsed.is_empty());
    }

    #[test]
    fn roster_parse_rejects_truncated_or_wrong_type_input() {
        assert!(parse_roster(&[]).is_none());
        assert!(parse_roster(&[CTL_HELLO]).is_none());

        // 声明 1 条成员但没有任何成员数据。
        let truncated = [CTL_ROSTER, 1, 0, 0, 0];
        assert!(parse_roster(&truncated).is_none());

        // 声称有 u32::MAX 条：不应尝试分配巨量内存，直接因数据不足返回 None。
        let mut huge = vec![CTL_ROSTER];
        huge.extend_from_slice(&u32::MAX.to_le_bytes());
        assert!(parse_roster(&huge).is_none());
    }
}
