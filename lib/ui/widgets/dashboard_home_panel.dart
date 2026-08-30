import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/pages/bookmarks_page.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/dashboard_connected_room_card.dart';
import 'package:astral_game/ui/widgets/dashboard_create_join_pill.dart';
import 'package:astral_game/ui/widgets/dashboard_scenery_card.dart';
import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:astral_game/utils/room_display.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 联机页：空闲为风景欢迎卡 + 底部信息 + FAB；已连接为房间卡。
class DashboardHomePanel extends StatelessWidget {
  const DashboardHomePanel({
    super.key,
    required this.isConnected,
    this.isLinking = false,
    this.username,
    this.roomDisplayName,
    this.roomRoleLabel,
    this.roomGameId,
    this.roomShortCode,
    this.isRoomHost = false,
    this.hostOnline = true,
    this.virtualIp,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
    required this.onBookmarkRoom,
  });

  final bool isConnected;

  /// 已有短码/会话，组网仍在进行中。
  final bool isLinking;
  final String? username;
  final String? roomDisplayName;
  final String? roomRoleLabel;
  final String? roomGameId;
  final String? roomShortCode;
  final bool isRoomHost;
  final bool hostOnline;
  final String? virtualIp;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;

  /// 「收藏当前房间」按钮回调；未连接时 UI 不会触发。
  final VoidCallback onBookmarkRoom;

  @override
  Widget build(BuildContext context) {
    final rs = getIt<RoomState>();
    final cs = getIt<ConnectionService>();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: isConnected
          ? Watch((context) {
              // 让 Watch 跟踪 bookmarksList + session 的变化
              final _ = rs.bookmarksList.value;
              final session = rs.session.value;
              final payload = cs.payloadFromCurrentSession();
              final isBookmarked = session != null && payload != null
                  ? rs.findBookmarkForPayload(payload) != null
                  : false;
              return ConnectedRoomCard(
                key: const ValueKey('connected'),
                roomDisplayName: roomDisplayName ?? '房间',
                roomRoleLabel: roomRoleLabel,
                roomGameId: roomGameId,
                roomShortCode: roomShortCode,
                isRoomHost: isRoomHost,
                hostOnline: hostOnline,
                isLinking: isLinking,
                virtualIp: virtualIp,
                onShare: onShareRoom,
                onDisconnect: onDisconnect,
                onBookmark: onBookmarkRoom,
                isBookmarked: isBookmarked,
              );
            })
          : _IdleHome(
              key: const ValueKey('idle'),
              username: username?.trim().isNotEmpty == true
                  ? username!.trim()
                  : 'Player',
              onCreate: onCreateRoom,
              onJoin: onJoinRoom,
            ),
    );
  }
}

class _IdleHome extends StatelessWidget {
  const _IdleHome({
    super.key,
    required this.username,
    required this.onCreate,
    required this.onJoin,
  });

  final String username;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final version = ClientRuntimeInfo.appVersion;
    final os = ClientRuntimeInfo.operatingSystemVersion;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DailySceneryCard(username: username),
            ),
            const SizedBox(height: 16),
            Watch((context) {
              final list = getIt<RoomState>().bookmarksList.value;
              if (list.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _BookmarkPreviewCard(
                  bookmarks: list,
                  onOpenAll: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const BookmarksPage(),
                      ),
                    );
                  },
                  onJoin: (b) => _handlePreviewJoin(context, b),
                ),
              );
            }),
            Text(
              'v$version',
              style: textTheme.labelMedium?.copyWith(
                color: palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              os,
              style: textTheme.labelSmall?.copyWith(
                color: palette.textTertiary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // 给右下角胶囊按钮留空
            const SizedBox(height: 64),
          ],
        ),
        Positioned(
          right: 0,
          bottom: 4,
          child: CreateJoinPill(
            onCreate: onCreate,
            onJoin: onJoin,
          ),
        ),
      ],
    );
  }
}

/// 首页「⭐ 我的收藏」预览：显示前 3 个 + 跳转到 BookmarksPage 入口。
class _BookmarkPreviewCard extends StatelessWidget {
  const _BookmarkPreviewCard({
    required this.bookmarks,
    required this.onOpenAll,
    required this.onJoin,
  });

  final List<Bookmark> bookmarks;
  final VoidCallback onOpenAll;
  final ValueChanged<Bookmark> onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final preview = bookmarks.take(3).toList();

    return AstralCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark, size: 18, color: palette.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '我的收藏（${bookmarks.length}）',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: onOpenAll,
                child: const Text('查看全部'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (var i = 0; i < preview.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: palette.divider.withValues(alpha: 0.3),
              ),
            _PreviewTile(
              bookmark: preview[i],
              onTap: () => onJoin(preview[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.bookmark, required this.onTap});
  final Bookmark bookmark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(
                bookmark.pinned ? Icons.push_pin : Icons.bookmark_outline,
                size: 16,
                color: palette.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookmarkDisplayLabel(bookmark),
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (bookmark.payload.gameName.trim().isNotEmpty)
                          bookmark.payload.gameName,
                        '收藏',
                      ].join(' · '),
                      style: textTheme.labelSmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首页预览卡点击「加入」：复用 BookmarksPage._handleJoin 逻辑。
Future<void> _handlePreviewJoin(BuildContext context, Bookmark b) async {
  final cs = getIt<ConnectionService>();
  final rs = getIt<RoomState>();
  if (cs.isConnecting) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在连接中，请稍候…')),
    );
    return;
  }
  try {
    // 不传 shortCode，让 _joinWithPayload 每次自动 create 新短码
    await cs.joinWithPayload(b.payload);
    // ignore: discarded_futures
    rs.touchBookmarkUsed(b.id);
  } on ConnectionAbortedException {
    return;
  } catch (e) {
    if (!context.mounted) return;
    final msg = e is ShareCodeException
        ? e.message
        : '加入失败：${e.runtimeType}';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
