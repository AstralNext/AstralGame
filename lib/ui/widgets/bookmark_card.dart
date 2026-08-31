import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/utils/room_display.dart';
import 'package:flutter/material.dart';

/// 收藏卡片操作集合（窄屏横卡 / 宽屏网格卡共用）。
class BookmarkCardActions {
  const BookmarkCardActions({
    required this.onJoin,
    required this.onShare,
    required this.onShortcut,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
  });

  final VoidCallback onJoin;
  final VoidCallback onShare;
  final VoidCallback onShortcut;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
}

/// 窄屏横版卡片：封面左 + 信息中 + 更多菜单右，点击整卡=加入房间。
class BookmarkCard extends StatelessWidget {
  const BookmarkCard({
    super.key,
    required this.bookmark,
    required this.actions,
  });

  final Bookmark bookmark;
  final BookmarkCardActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    return AstralCard(
      onTap: actions.onJoin,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 92,
            child: Stack(
              children: [
                Positioned.fill(child: _Cover(bookmark: bookmark)),
                if (bookmark.pinned)
                  const Positioned(top: 4, right: 4, child: _PinBadge()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bookmarkDisplayLabel(bookmark),
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _gameLabel(bookmark),
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  relativeTime(bookmark.sortKey),
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          BookmarkActionsMenu(bookmark: bookmark, actions: actions),
        ],
      ),
    );
  }
}

/// 宽屏 Steam 游戏墙式网格卡：封面铺满卡身上部，标题/游戏名收在卡片内部底部。
class BookmarkGridCard extends StatelessWidget {
  const BookmarkGridCard({
    super.key,
    required this.bookmark,
    required this.actions,
  });

  final Bookmark bookmark;
  final BookmarkCardActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    return AstralCard(
      onTap: actions.onJoin,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Cover(bookmark: bookmark),
                if (bookmark.pinned)
                  const Positioned(top: 6, left: 6, child: _PinBadge()),
                Positioned(
                  top: 2,
                  right: 2,
                  child: BookmarkActionsMenu(
                    bookmark: bookmark,
                    actions: actions,
                    onImage: true,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bookmarkDisplayLabel(bookmark),
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _gameLabel(bookmark),
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 封面：注册过的游戏用媒体图（cover 填充），否则用游戏名兜底块。
class _Cover extends StatelessWidget {
  const _Cover({required this.bookmark});
  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final game = GameCatalog.byId(bookmark.payload.gameId);
    if (game == null) return _FallbackCover(bookmark: bookmark);
    return GameMediaImage(
      source: game.resolvedGridAsset,
      errorBuilder: (_, _, _) => _FallbackCover(bookmark: bookmark),
    );
  }
}

class _FallbackCover extends StatelessWidget {
  const _FallbackCover({required this.bookmark});
  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: palette.accentMuted,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_esports, size: 28, color: palette.accent),
          const SizedBox(height: 6),
          Text(
            bookmark.payload.gameName.isEmpty
                ? 'Room'
                : bookmark.payload.gameName,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PinBadge extends StatelessWidget {
  const _PinBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.push_pin_rounded, size: 12, color: Colors.white),
    );
  }
}

/// 「更多操作」菜单：置顶 / 分享 / 快捷方式 / 编辑 / 删除。
class BookmarkActionsMenu extends StatelessWidget {
  const BookmarkActionsMenu({
    super.key,
    required this.bookmark,
    required this.actions,
    this.onImage = false,
  });

  final Bookmark bookmark;
  final BookmarkCardActions actions;

  /// 菜单图标叠在封面图上时用白色圆底，保证深色封面上可见。
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final icon = Icon(
      Icons.more_vert_rounded,
      size: 18,
      color: onImage ? Colors.white : palette.textSecondary,
    );
    final trigger = onImage
        ? Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: icon,
          )
        : icon;

    return PopupMenuButton<String>(
      tooltip: '更多操作',
      position: PopupMenuPosition.under,
      color: palette.card,
      onSelected: (key) => switch (key) {
        'pin' => actions.onTogglePin(),
        'share' => actions.onShare(),
        'shortcut' => actions.onShortcut(),
        'edit' => actions.onEdit(),
        'delete' => actions.onDelete(),
        _ => {},
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'pin',
          child: _MenuItemRow(
            icon: bookmark.pinned
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined,
            label: bookmark.pinned ? '取消置顶' : '置顶',
          ),
        ),
        const PopupMenuItem(
          value: 'share',
          child: _MenuItemRow(icon: Icons.share_rounded, label: '分享'),
        ),
        const PopupMenuItem(
          value: 'shortcut',
          child: _MenuItemRow(icon: Icons.shortcut_rounded, label: '快捷方式'),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: _MenuItemRow(icon: Icons.edit_rounded, label: '编辑'),
        ),
        PopupMenuItem(
          value: 'delete',
          child: _MenuItemRow(
            icon: Icons.delete_outline,
            label: '删除',
            color: palette.error,
          ),
        ),
      ],
      child: trigger,
    );
  }
}

class _MenuItemRow extends StatelessWidget {
  const _MenuItemRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).textTheme.bodyMedium?.color;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: c)),
      ],
    );
  }
}

String _gameLabel(Bookmark bookmark) {
  final game = GameCatalog.byId(bookmark.payload.gameId);
  return game?.displayName ??
      (bookmark.payload.gameName.trim().isEmpty
          ? bookmark.payload.networkName
          : bookmark.payload.gameName.trim());
}

/// 人类可读相对时间（无 intl 依赖，够用即可）。
String relativeTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.isNegative) return '刚刚';
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7} 周前';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30} 个月前';
  return '${diff.inDays ~/ 365} 年前';
}
