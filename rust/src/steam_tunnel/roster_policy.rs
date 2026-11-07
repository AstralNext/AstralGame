//! 成员表策略（纯函数，无 Steam 依赖）。
//!
//! 两段过期判定：
//! - 在线成员心跳超时（[`ONLINE_TIMEOUT`]）：连接还在但长时间没有任何消息；
//! - 离线成员宽限期（[`OFFLINE_GRACE`]）：已经标记离线，但保留一段时间用于重连，
//!   超时后从成员表真正删除，避免「离线行」永久堆在列表里。
//!
//! 宽限期取 30 秒的理由：与在线心跳超时一致；客人重连间隔是 3 秒，30 秒相当于
//! 10 次重连机会，足以扛住一次短暂丢包/Steam 抖动，又不会让幽灵行长期停留。

use std::time::{Duration, Instant};

/// 在线成员的心跳超时阈值。
pub const ONLINE_TIMEOUT: Duration = Duration::from_secs(30);

/// 离线成员从「标记离线」到「真正摘除」的宽限期。
pub const OFFLINE_GRACE: Duration = Duration::from_secs(30);

/// 成员表过期判定所需的最小字段集，与 `engine::Member` 解耦。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MemberView {
    pub steam_id: u64,
    pub is_self: bool,
    pub is_host: bool,
    pub online: bool,
    /// 最后一次收到该成员消息的时间。
    pub last_seen: Instant,
    /// 首次观察到离线的时间；在线时为 `None`。
    pub offline_since: Option<Instant>,
}

/// 需要从成员表摘除的成员。
///
/// 房主自己永远不会被摘除；普通成员要么心跳超时，要么离线超过宽限期。
pub fn prune_plan(members: &[MemberView], now: Instant) -> Vec<u64> {
    members
        .iter()
        .filter(|m| {
            if m.is_host || m.is_self {
                return false;
            }
            if m.online {
                now.duration_since(m.last_seen) > ONLINE_TIMEOUT
            } else {
                m.offline_since
                    .map(|at| now.duration_since(at) >= OFFLINE_GRACE)
                    .unwrap_or(false)
            }
        })
        .map(|m| m.steam_id)
        .collect()
}

/// 对 UI 可见的成员。
///
/// 摘除由 [`prune_plan`] 负责；这里只返回仍在成员表里的人，离线且未过宽限期的
/// 成员保留（UI 用 `online` 位区分显示），便于重连时原地恢复。
pub fn visible_members(members: &[MemberView]) -> Vec<u64> {
    members.iter().map(|m| m.steam_id).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const SELF_ID: u64 = 1001;
    const GUEST_ID: u64 = 2002;

    fn host_self(last_seen: Instant) -> MemberView {
        MemberView {
            steam_id: SELF_ID,
            is_self: true,
            is_host: true,
            online: true,
            last_seen,
            offline_since: None,
        }
    }

    fn guest(online: bool, last_seen: Instant, offline_since: Option<Instant>) -> MemberView {
        MemberView {
            steam_id: GUEST_ID,
            is_self: false,
            is_host: false,
            online,
            last_seen,
            offline_since,
        }
    }

    #[test]
    fn offline_member_within_grace_is_kept() {
        let now = Instant::now();
        let members = [
            host_self(now),
            guest(false, now, Some(now - Duration::from_secs(29))),
        ];

        assert!(prune_plan(&members, now).is_empty());
    }

    #[test]
    fn offline_member_beyond_grace_is_pruned() {
        let now = Instant::now();
        let members = [
            host_self(now),
            guest(false, now, Some(now - Duration::from_secs(31))),
        ];

        assert_eq!(prune_plan(&members, now), vec![GUEST_ID]);
    }

    #[test]
    fn offline_without_timestamp_is_not_pruned() {
        let now = Instant::now();
        let members = [host_self(now), guest(false, now, None)];

        assert!(prune_plan(&members, now).is_empty());
    }

    #[test]
    fn online_member_with_stale_heartbeat_is_pruned() {
        let now = Instant::now();
        let members = [
            host_self(now),
            guest(true, now - Duration::from_secs(31), None),
        ];

        assert_eq!(prune_plan(&members, now), vec![GUEST_ID]);
    }

    #[test]
    fn online_member_within_timeout_is_kept() {
        let now = Instant::now();
        let members = [
            host_self(now),
            guest(true, now - Duration::from_secs(29), None),
        ];

        assert!(prune_plan(&members, now).is_empty());
    }

    #[test]
    fn host_self_is_never_pruned_even_when_stale() {
        let now = Instant::now();
        let members = [host_self(now - Duration::from_secs(600))];

        assert!(prune_plan(&members, now).is_empty());
    }
}
