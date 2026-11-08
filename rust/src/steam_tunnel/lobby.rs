//! Steam 大厅（Lobby）发现：字段规范、本地二次校验与列表过期策略。
//!
//! 只做纯逻辑，不碰 Steam API：引擎负责调用 Steam，拿到 key/value 后交给这里
//! 解析与校验，这样「哪些房该进列表」可以脱离 Steam 客户端单测。
//!
//! 三层校验（见 `docs/steam-room-discovery.md`）：
//! 1. `request_lobby_list` 的 `ag_game` 服务端字符串过滤；
//! 2. 拿到结果后在这里做本地二次校验（`ag_game` / `ag_ver` / `ag_gate`）；
//! 3. 进房后 HELLO 里再带一次 `game_id`，由房主校验。

use std::time::{Duration, Instant};

/// 大厅元数据 key（`ag_` 命名空间）。
pub const KEY_GAME: &str = "ag_game";
pub const KEY_VER: &str = "ag_ver";
pub const KEY_GATE: &str = "ag_gate";
pub const KEY_NAME: &str = "ag_name";
pub const KEY_HOST: &str = "ag_host";
pub const KEY_PLAYERS: &str = "ag_players";
pub const KEY_CAP: &str = "ag_cap";

/// 组网协议版本；与 `proto::VERSION` 是两回事，这里只用于大厅筛选。
pub const PROTOCOL_VERSION: &str = "1";

/// 列表本地有效期。
///
/// 搜索成功时整表替换；只有搜索失败时才回放缓存，且最多回放 5 分钟。
/// 5 分钟足以覆盖一次 Steam 回调抖动，又不会把早已关掉的房长期留在列表里。
pub const LIST_TTL: Duration = Duration::from_secs(300);

/// 房间门槛。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Gate {
    /// 只有全工具统一基础口令。
    Basic,
    /// 基础口令 + 房主自设的额外密码。
    Double,
    /// 无门槛（必须显式二次确认才允许开）。
    Open,
}

impl Gate {
    pub fn as_str(self) -> &'static str {
        match self {
            Gate::Basic => "basic",
            Gate::Double => "double",
            Gate::Open => "open",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim() {
            "basic" => Some(Gate::Basic),
            "double" => Some(Gate::Double),
            "open" => Some(Gate::Open),
            _ => None,
        }
    }
}

/// 一次搜索里的一条大厅快照。
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LobbySnapshot {
    pub lobby_id: u64,
    pub game_id: String,
    pub version: String,
    pub gate: Gate,
    pub name: String,
    pub host_steam_id: String,
    pub players: u32,
    pub capacity: u32,
}

/// 解析 Steam 邀请携带的 connect string（形如 `+connect_lobby 1234567890`）。
///
/// 应用未启动时 Steam 会用这个参数拉起进程，进程里唯一的邀请信息就在 argv；
/// 不解析它等于好友邀请静默失效。
pub fn parse_connect_lobby(connect: &str) -> Option<u64> {
    let mut parts = connect.split_whitespace();
    while let Some(part) = parts.next() {
        let raw = if let Some(v) = part.strip_prefix("+connect_lobby=") {
            v
        } else if part == "+connect_lobby" {
            parts.next()?
        } else {
            continue;
        };
        if let Ok(id) = raw.trim_matches('"').parse::<u64>() {
            if id != 0 {
                return Some(id);
            }
        }
    }
    None
}

/// 从完整命令行里找 `+connect_lobby`。
pub fn parse_connect_lobby_args<I: IntoIterator<Item = String>>(args: I) -> Option<u64> {
    parse_connect_lobby(&args.into_iter().collect::<Vec<_>>().join(" "))
}

/// 把游戏 id 规范化成 `ag_game` 允许的稳定 slug。
///
/// 只保留 ASCII 小写字母、数字、`-` 与 `_`，最长 32 字节；规范化后为空则拒绝。
pub fn normalize_game_id(raw: &str) -> Option<String> {
    let mut out = String::with_capacity(raw.len().min(32));
    for ch in raw.trim().chars() {
        if out.len() >= 32 {
            break;
        }
        let lower = ch.to_ascii_lowercase();
        if lower.is_ascii_lowercase() || lower.is_ascii_digit() || lower == '-' || lower == '_' {
            out.push(lower);
        }
    }
    if out.is_empty() {
        None
    } else {
        Some(out)
    }
}

/// 从大厅的 key/value 列表解析快照；缺必填 key 或缺人数字段都不进列表。
///
/// 未知 `ag_*` key 一律忽略；`ag_name` 解析失败不影响进房，只回落成占位名。
pub fn parse_snapshot(
    lobby_id: u64,
    pairs: &[(String, String)],
    players: u32,
    capacity: u32,
    host_steam_id: &str,
) -> Option<LobbySnapshot> {
    let mut game_id = None;
    let mut version = None;
    let mut gate = None;
    let mut name = String::new();
    let mut host = String::new();

    for (key, value) in pairs {
        match key.as_str() {
            KEY_GAME => game_id = Some(value.trim().to_string()),
            KEY_VER => version = Some(value.trim().to_string()),
            KEY_GATE => gate = Gate::parse(value),
            KEY_NAME => name = value.trim().to_string(),
            KEY_HOST => host = value.trim().to_string(),
            _ => {}
        }
    }

    let game_id = game_id.filter(|v| !v.is_empty())?;
    let version = version.filter(|v| !v.is_empty())?;
    let gate = gate?;
    if name.is_empty() {
        name = "未命名房间".to_string();
    }
    if host.is_empty() {
        host = host_steam_id.trim().to_string();
    }
    Some(LobbySnapshot {
        lobby_id,
        game_id,
        version,
        gate,
        name,
        host_steam_id: host,
        players,
        capacity,
    })
}

/// 本地二次校验：不满足即丢弃，不进入列表。
///
/// `expected_game_id` 为空表示「全部」：跳过游戏比对，只校验协议版本。
pub fn validate(snapshot: &LobbySnapshot, expected_game_id: &str) -> Result<(), String> {
    if !expected_game_id.is_empty()
        && !snapshot.game_id.eq_ignore_ascii_case(expected_game_id)
    {
        return Err("游戏标识不一致".to_string());
    }
    if snapshot.version != PROTOCOL_VERSION {
        return Err(format!(
            "房间协议版本 {} 与本机 {} 不一致",
            snapshot.version, PROTOCOL_VERSION
        ));
    }
    Ok(())
}

/// 进房前的门槛校验：`double` 需要额外密码，`open` 需要用户显式确认。
pub fn gate_requires_extra_password(gate: Gate) -> bool {
    gate == Gate::Double
}

/// 搜索结果的本地缓存。
///
/// 正常情况下每次搜索成功都整表替换；搜索失败（Steam 回调丢失 / 超时）时
/// 回放 [LIST_TTL] 内的旧结果，避免列表瞬间清空。
#[derive(Default)]
pub struct LobbyCache {
    items: Vec<(Instant, LobbySnapshot)>,
}

impl LobbyCache {
    pub fn replace(&mut self, items: Vec<LobbySnapshot>, now: Instant) {
        self.items = items.into_iter().map(|s| (now, s)).collect();
    }

    pub fn fresh(&self, now: Instant) -> Vec<LobbySnapshot> {
        self.items
            .iter()
            .filter(|(at, _)| now.saturating_duration_since(*at) < LIST_TTL)
            .map(|(_, s)| s.clone())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pairs(game: &str, ver: &str, gate: &str) -> Vec<(String, String)> {
        vec![
            (KEY_GAME.to_string(), game.to_string()),
            (KEY_VER.to_string(), ver.to_string()),
            (KEY_GATE.to_string(), gate.to_string()),
        ]
    }

    #[test]
    fn normalize_keeps_ascii_slug_and_rejects_empty() {
        assert_eq!(normalize_game_id("Squad"), Some("squad".to_string()));
        assert_eq!(
            normalize_game_id("  Deep Rock v1.0  "),
            Some("deeprockv10".to_string())
        );
        assert_eq!(normalize_game_id("收获日"), None);
        assert_eq!(normalize_game_id("   "), None);
        // 超长截断到 32 字节。
        let long = "a".repeat(80);
        assert_eq!(normalize_game_id(&long).unwrap().len(), 32);
    }

    #[test]
    fn parse_snapshot_ignores_unknown_keys_and_fills_defaults() {
        let mut p = pairs("squad", "1", "basic");
        p.push(("ag_unknown".to_string(), "x".to_string()));
        let s = parse_snapshot(7, &p, 2, 8, "76561198000000000").expect("应能解析");
        assert_eq!(s.lobby_id, 7);
        assert_eq!(s.game_id, "squad");
        assert_eq!(s.gate, Gate::Basic);
        assert_eq!(s.name, "未命名房间");
        assert_eq!(s.host_steam_id, "76561198000000000");
        assert_eq!(s.players, 2);
        assert_eq!(s.capacity, 8);
    }

    #[test]
    fn parse_snapshot_requires_game_version_and_gate() {
        assert!(parse_snapshot(1, &pairs("", "1", "basic"), 1, 4, "").is_none());
        assert!(parse_snapshot(1, &pairs("squad", "", "basic"), 1, 4, "").is_none());
        // 未知门槛：宁可不进列表，也不放宽判断。
        assert!(parse_snapshot(1, &pairs("squad", "1", "whatever"), 1, 4, "").is_none());
    }

    #[test]
    fn validate_rejects_other_game_and_version_mismatch() {
        let s = parse_snapshot(1, &pairs("squad", "1", "basic"), 1, 4, "").unwrap();
        assert!(validate(&s, "squad").is_ok());
        assert!(validate(&s, "SQUAD").is_ok());
        assert!(validate(&s, "scfa").is_err());

        let old = parse_snapshot(2, &pairs("squad", "0", "basic"), 1, 4, "").unwrap();
        assert!(validate(&old, "squad").is_err());
    }

    #[test]
    fn gate_parsing_and_extra_password_rule() {
        assert_eq!(Gate::parse(" basic "), Some(Gate::Basic));
        assert_eq!(Gate::parse("double"), Some(Gate::Double));
        assert_eq!(Gate::parse("open"), Some(Gate::Open));
        assert_eq!(Gate::parse(""), None);
        assert!(gate_requires_extra_password(Gate::Double));
        assert!(!gate_requires_extra_password(Gate::Basic));
        assert!(!gate_requires_extra_password(Gate::Open));
    }

    #[test]
    fn connect_lobby_argument_forms() {
        assert_eq!(parse_connect_lobby("+connect_lobby 123"), Some(123));
        assert_eq!(parse_connect_lobby("+connect_lobby=456"), Some(456));
        assert_eq!(parse_connect_lobby("  +connect_lobby   \"789\" "), Some(789));
        assert_eq!(parse_connect_lobby("+connect 1.2.3.4:27015"), None);
        assert_eq!(parse_connect_lobby("+connect_lobby 0"), None);
        assert_eq!(parse_connect_lobby(""), None);

        let argv = vec!["AstralGame.exe".to_string(), "+connect_lobby".to_string(), "42".to_string()];
        assert_eq!(parse_connect_lobby_args(argv), Some(42));
        let none = vec!["AstralGame.exe".to_string()];
        assert_eq!(parse_connect_lobby_args(none), None);
    }

    #[test]
    fn cache_replaces_on_success_and_expires_after_ttl() {
        let now = Instant::now();
        let mut cache = LobbyCache::default();
        let a = parse_snapshot(1, &pairs("squad", "1", "basic"), 1, 4, "").unwrap();
        let b = parse_snapshot(2, &pairs("squad", "1", "basic"), 1, 4, "").unwrap();

        cache.replace(vec![a.clone(), b], now);
        assert_eq!(cache.fresh(now).len(), 2);

        // 搜索成功但房间已关：整表替换，旧条目立即消失。
        let c = parse_snapshot(3, &pairs("squad", "1", "double"), 1, 4, "").unwrap();
        cache.replace(vec![c.clone()], now);
        assert_eq!(cache.fresh(now), vec![c.clone()]);

        // TTL 到点后不再回放。
        assert!(cache.fresh(now + LIST_TTL).is_empty());
    }
}
