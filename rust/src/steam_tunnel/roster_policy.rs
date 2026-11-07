//! 成员表策略（纯函数，无 Steam 依赖）。
//!
//! 抽出来的目的：在没有第二个 Steam 账号的情况下，也能用确定性单测复现
//! 「成员离线后永久留在列表里」的行为。
//!
//! 当前语义（与 `engine` 现网行为逐条对齐）：
//! - `remove_member` 只把成员标记为 `online = false`，不从成员表删除；
//! - `prune_plan` 只处理「在线且心跳超时」的成员，已离线成员不会被再次清理；
//! - `visible_members` 全量返回，离线成员照常进入 UI 快照。
//!
//! 因此一个成员只要掉线一次，就会以「离线」状态永久保留。本模块的单测
//! 把这一行为固定为回归基线，修复时再同步更新断言。

use std::time::{Duration, Instant};

/// 在线成员的心跳超时阈值。
pub const ONLINE_TIMEOUT: Duration = Duration::from_secs(30);

/// 成员表过期判定所需的最小字段集，与 `engine::Member` 解耦。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MemberView {
    pub steam_id: u64,
    pub is_self: bool,
    pub is_host: bool,
    pub online: bool,
    /// 最后一次收到该成员消息的时间；离线后即离线开始时间。
    pub last_seen: Instant,
}

/// 需要摘除的成员。
///
/// 只覆盖「在线但心跳超时」；已离线成员不在此列，这是幽灵成员的直接原因。
pub fn prune_plan(members: &[MemberView], now: Instant) -> Vec<u64> {
    members
        .iter()
        .filter(|m| {
            !m.is_host && m.online && !m.is_self && now.duration_since(m.last_seen) > ONLINE_TIMEOUT
        })
        .map(|m| m.steam_id)
        .collect()
}

/// 对 UI 可见的成员。
///
/// 现网行为是全量返回（含离线），所以离线成员会一直显示。
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
        }
    }

    fn guest(online: bool, last_seen: Instant) -> MemberView {
        MemberView {
            steam_id: GUEST_ID,
            is_self: false,
            is_host: false,
            online,
            last_seen,
        }
    }

    #[test]
    fn offline_member_is_never_pruned_but_still_visible() {
        let now = Instant::now();
        let members = [
            host_self(now),
            // 成员已掉线 60 秒：remove_member 只把它标成离线。
            guest(false, now - Duration::from_secs(60)),
        ];

        assert!(
            prune_plan(&members, now).is_empty(),
            "离线成员不应进入清理计划——这正是幽灵成员的根因"
        );
        assert_eq!(
            visible_members(&members),
            vec![SELF_ID, GUEST_ID],
            "离线成员仍会被输出到 UI 快照"
        );
    }

    #[test]
    fn online_member_with_stale_heartbeat_is_pruned() {
        let now = Instant::now();
        let members = [
            host_self(now),
            // 连接还在、但 31 秒没收到任何消息。
            guest(true, now - Duration::from_secs(31)),
        ];

        assert_eq!(prune_plan(&members, now), vec![GUEST_ID]);
    }

    #[test]
    fn online_member_within_timeout_is_kept() {
        let now = Instant::now();
        let members = [host_self(now), guest(true, now - Duration::from_secs(29))];

        assert!(prune_plan(&members, now).is_empty());
    }

    #[test]
    fn host_self_is_never_pruned_even_when_stale() {
        let now = Instant::now();
        let members = [host_self(now - Duration::from_secs(600))];

        assert!(prune_plan(&members, now).is_empty());
    }
}
