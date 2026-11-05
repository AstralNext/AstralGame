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
    let src = Ipv4Addr::from(u32::from_le_bytes([
        data[4], data[5], data[6], data[7],
    ]));
    let dst = Ipv4Addr::from(u32::from_le_bytes([
        data[8], data[9], data[10], data[11],
    ]));
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
    Some(Ipv4Addr::new(packet[16], packet[17], packet[18], packet[19]))
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
