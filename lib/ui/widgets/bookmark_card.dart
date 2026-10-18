import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/bookmark_cover_store.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/utils/room_display.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 收藏卡片操作集合（窄屏横卡 / 宽屏网格卡共用）。
class BookmarkCardActions {
  const BookmarkCardActions({
    required this.onJoin,
    required this.onShare,
    required this.onShortcut,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
    required this.onChangeCover,
    required this.onRemoveCover,
  });

  final VoidCallback onJoin;
  final VoidCallback onShare;
  final VoidCallback onShortcut;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  /// 选一张本地图片作为该收藏的封面。
  final VoidCallback onChangeCover;

  /// 去掉自定义封面，回到游戏默认封面。
  final VoidCallback onRemoveCover;
}

/// 窄屏横版卡片：封面左 + 信息中 + 明确的「加入」按钮右。
///
/// 手机上没有 hover，也没有稳定的右键：点整卡（或长按）打开底部操作面板，
/// 只有右侧的「加入」按钮会直接连接房间，避免误触。
class BookmarkCard extends StatelessWidget {
  const BookmarkCard({
    super.key,
    required this.bookmark,
    required this.actions,
    required this.onOpenActions,
  });

  final Bookmark bookmark;
  final BookmarkCardActions actions;

  /// 打开底部操作面板（加入 / 置顶 / 分享 / 编辑 / 封面 / 删除）。
  final VoidCallback onOpenActions;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    return AstralCard(
      onTap: onOpenActions,
      onLongPress: onOpenActions,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 92,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Positioned.fill(child: BookmarkCover(bookmark: bookmark)),
                  if (bookmark.pinned)
                    const Positioned(top: 4, right: 4, child: _PinBadge()),
                ],
              ),
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
                  bookmarkGameLabel(bookmark),
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
          const SizedBox(width: 8),
          _JoinPillButton(onPressed: actions.onJoin),
        ],
      ),
    );
  }
}

/// 卡片右侧的主操作：一眼可见、触控区域足够大的「加入」胶囊。
class _JoinPillButton extends StatelessWidget {
  const _JoinPillButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: palette.accent,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40, minWidth: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: 18,
                  color: palette.onAccent,
                ),
                const SizedBox(width: 2),
                Text(
                  '加入',
                  style: textTheme.labelMedium?.copyWith(
                    color: palette.onAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
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
                BookmarkCover(bookmark: bookmark),
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
                  bookmarkGameLabel(bookmark),
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

/// 封面：优先用户自定义封面，其次注册过的游戏用媒体图（cover 填充），
/// 都没有时用游戏名兜底块。
///
/// 公开给手机端操作面板复用，保证卡片和面板里的封面始终一致。
class BookmarkCover extends StatelessWidget {
  const BookmarkCover({super.key, required this.bookmark});
  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final store = getIt<BookmarkCoverStore>();
    return Watch((context) {
      // 换/移除封面后靠 revision 触发重建
      store.revision.value;
      final custom = store.fileFor(bookmark.id);
      if (custom != null) {
        return Image.file(
          custom,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _gameCover(bookmark),
        );
      }
      return _gameCover(bookmark);
    });
  }
}

/// 游戏自带封面（可能来自本地 asset，也可能走线上 CDN）。
Widget _gameCover(Bookmark bookmark) {
  final game = GameCatalog.byId(bookmark.payload.gameId);
  if (game == null) return _FallbackCover(bookmark: bookmark);
  return GameMediaImage(
    source: game.resolvedGridAsset,
    errorBuilder: (_, _, _) => _FallbackCover(bookmark: bookmark),
  );
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

    final store = getIt<BookmarkCoverStore>();
    return Watch((context) {
      final hasCover = store.hasCover(bookmark.id);
      return PopupMenuButton<String>(
        tooltip: '更多操作',
        position: PopupMenuPosition.under,
        color: palette.card,
        onSelected: (key) => switch (key) {
          'pin' => actions.onTogglePin(),
          'share' => actions.onShare(),
          'shortcut' => actions.onShortcut(),
          'cover' => actions.onChangeCover(),
          'remove_cover' => actions.onRemoveCover(),
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
            value: 'cover',
            child: _MenuItemRow(icon: Icons.image_outlined, label: '更换封面'),
          ),
          if (hasCover)
            const PopupMenuItem(
              value: 'remove_cover',
              child: _MenuItemRow(
                icon: Icons.hide_image_outlined,
                label: '移除封面',
              ),
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
    });
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

/// 卡片与操作面板共用的游戏名（优先注册表里的显示名）。
String bookmarkGameLabel(Bookmark bookmark) {
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
