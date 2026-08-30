import 'dart:async';
import 'dart:async';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/services/shortcut_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/utils/room_display.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:astral_game/utils/room_share_actions.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 我的收藏页。
///
/// - 左侧竖版游戏封面 + 游戏名 + 用户起名 + 备注
/// - 搜索：名字/游戏/短码/备注
/// - 假分页：每页 [_pageSize] 条
/// - 操作：加入 / 分享 / 编辑 / 删除 / 置顶
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  static const int _pageSize = 20;

  final RoomState _roomState = getIt<RoomState>();
  final ConnectionService _connectionService = getIt<ConnectionService>();
  final TextEditingController _search = TextEditingController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() => _page = 0);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Bookmark> _filtered(List<Bookmark> all) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((b) => b.searchHaystack.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.astralPalette.background,
      appBar: AppBar(
        title: const Text('我的收藏'),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '搜索：房间名 / 游戏 / 短码 / 备注',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: Watch((context) {
        final all = _roomState.bookmarksList.value;
        final filtered = _filtered(all);
        final pinned = filtered.where((b) => b.pinned).toList();
        final unpinned = filtered.where((b) => !b.pinned).toList();
        final totalPages = _totalPages(unpinned.length);
        final pageIndex = _page.clamp(0, totalPages == 0 ? 0 : totalPages - 1);
        final unpinnedSlice = unpinned.isEmpty
            ? const <Bookmark>[]
            : unpinned.sublist(
                pageIndex * _pageSize,
                (pageIndex * _pageSize + _pageSize).clamp(0, unpinned.length),
              );
        final isEmpty = all.isEmpty;
        final noResultAfterFilter =
            all.isNotEmpty && filtered.isEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: isEmpty
                  ? _EmptyState(onGoHome: () => Navigator.pop(context))
                  : noResultAfterFilter
                      ? _NoSearchResultState(onClear: () {
                          _search.clear();
                        })
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                            16,
                            12,
                            16,
                            72,
                          ),
                          children: [
                            if (pinned.isNotEmpty) ...[
                              _SectionHeader(
                                title: '🌟 置顶',
                                count: pinned.length,
                              ),
                              const SizedBox(height: 8),
                              for (final b in pinned)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 12),
                                  child: _BookmarkCard(
                                    bookmark: b,
                                    onJoin: () => _handleJoin(b),
                                    onShare: () => _handleShare(b),
                                    onShortcut: () => _handleShortcut(b),
                                    onEdit: () => _handleEdit(b),
                                    onDelete: () => _handleDelete(b),
                                  ),
                                ),
                              const SizedBox(height: 8),
                            ],
                            if (unpinned.isNotEmpty) ...[
                              _SectionHeader(
                                title: '全部收藏',
                                count: unpinned.length,
                              ),
                              const SizedBox(height: 8),
                              for (final b in unpinnedSlice)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 12),
                                  child: _BookmarkCard(
                                    bookmark: b,
                                    onJoin: () => _handleJoin(b),
                                    onShare: () => _handleShare(b),
                                    onShortcut: () => _handleShortcut(b),
                                    onEdit: () => _handleEdit(b),
                                    onDelete: () => _handleDelete(b),
                                  ),
                                ),
                            ],
                          ],
                        ),
            ),
            if (!isEmpty && !noResultAfterFilter && totalPages > 1)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: pageIndex == 0
                            ? null
                            : () => setState(() => _page = pageIndex - 1),
                        child: const Text('上一页'),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${pageIndex + 1} / $totalPages',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: pageIndex + 1 < totalPages
                            ? () => setState(() => _page = pageIndex + 1)
                            : null,
                        child: const Text('下一页'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }

  int _totalPages(int length) {
    if (length == 0) return 0;
    return (length / _pageSize).ceil();
  }

  // ============ 操作 ============

  Future<void> _handleJoin(Bookmark b) async {
    if (_connectionService.isConnecting) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在连接中，请稍候…')),
      );
      return;
    }
    try {
      // 不传 shortCode，让 _joinWithPayload 每次自动 create 新短码
      await _connectionService.joinWithPayload(b.payload);
      // ignore: discarded_futures
      _roomState.touchBookmarkUsed(b.id);
      if (!mounted) return;
      // 连接成功后留在当前页还是返回首页均可；这里 pop 回首页让用户看到"已连接"卡片
      Navigator.of(context).pop();
    } on ConnectionAbortedException {
      // 用户主动取消，静默
      return;
    } catch (e) {
      if (!mounted) return;
      final msg = e is ShareCodeException
          ? e.message
          : '加入失败：${e.runtimeType}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _handleShare(Bookmark b) async {
    // 每次都 create 新短码（旧的早就过期了），并回写到 bookmark
    String? shareCode;
    String? adminToken;
    try {
      final result =
          await _connectionService.createShareCodeForPayload(b.payload);
      shareCode = result.code;
      adminToken = result.adminToken;
      // 回写到 bookmark，之后 Dashboard 会话分享也能用新短码
      unawaited(_roomState.refreshBookmarkShareCode(
        b.payload,
        shortCode: shareCode,
        adminToken: adminToken,
      ));
    } on ShareCodeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('短码服务暂不可用（${e.message}），改用离线邀请链接'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('无法生成短码：$e，改用离线邀请链接'),
        ));
      }
    }
    if (!mounted) return;

    final url = buildJoinShareUrl(
      shortCode: shareCode,
      offlineInvite: encodeOfflineInvite(b.payload),
    );
    await shareJoinInvite(
      context: context,
      url: url.isEmpty ? encodeOfflineInvite(b.payload) : url,
      gameName: b.payload.gameName,
    );
  }


  Future<void> _handleShortcut(Bookmark b) async {
    final ctx = context;
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('正在创建快捷方式…')),
      );
      final ok = await getIt<ShortcutService>().createDesktopShortcut(
        bookmark: b,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: ok
            ? Text('已创建「${b.displayName}」快捷方式')
            : const Text('已取消创建'),
      ));
    } on ShortcutException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        ShortcutErrorCode.noPermission => '权限不足：请在系统设置中允许 Astral Game 创建快捷方式',
        ShortcutErrorCode.unsupported => '当前系统不支持桌面快捷方式',
        ShortcutErrorCode.desktopNotFound => '无法定位桌面路径（是否被 OneDrive 重定向？）',
        _ => e.message,
      };
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('创建失败：$e')),
      );
    }
  }

  Future<void> _handleEdit(Bookmark old) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (c) => _BookmarkEditDialog(bookmark: old),
    );
    if (result == null) return;
    final next = old.copyWith(
      customName: result.customName,
      pinned: result.pinned,
    );
    await _roomState.upsertBookmark(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已更新')),
      );
    }
  }

  Future<void> _handleDelete(Bookmark b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('取消收藏？'),
        content: Text('「${bookmarkDisplayLabel(b)}」将从收藏中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _roomState.removeBookmark(b.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已取消收藏')),
      );
    }
  }
}

// ============ 子组件 ============

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        children: [
          Text(title,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: palette.textPrimary,
              )),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: palette.accentMuted,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count',
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.accent,
                )),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onGoHome});
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_add_outlined,
                size: 72, color: palette.textTertiary),
            const SizedBox(height: 16),
            Text('还没有收藏的房间',
                style: textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              '加入或创建房间后，点右上角 ⭐ 即可保存',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: onGoHome,
              child: const Text('返回联机页'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchResultState extends StatelessWidget {
  const _NoSearchResultState({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 64, color: palette.textTertiary),
            const SizedBox(height: 12),
            Text('没有匹配的收藏',
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextButton(onPressed: onClear, child: const Text('清空搜索词')),
          ],
        ),
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  const _BookmarkCard({
    required this.bookmark,
    required this.onJoin,
    required this.onShare,
    required this.onShortcut,
    required this.onEdit,
    required this.onDelete,
  });

  final Bookmark bookmark;
  final VoidCallback onJoin;
  final VoidCallback onShare;
  final VoidCallback onShortcut;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final game = GameCatalog.byId(bookmark.payload.gameId);
    final displayName = bookmark.payload.displayName?.trim();
    final gameName = bookmark.payload.gameName.trim();

    return AstralCard(
      onTap: onJoin,
      padding: const EdgeInsets.all(14),
      radius: AppDimensions.radiusMd,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            height: 132,
            child: Stack(
              children: [
                Positioned.fill(
                  child: game != null
                      ? GameGridCover(
                          game: game,
                          width: 88,
                          height: 132,
                          borderRadius: 12,
                        )
                      : _FallbackGameCover(bookmark: bookmark),
                ),
                if (bookmark.pinned)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Icon(
                        Icons.push_pin_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bookmarkDisplayLabel(bookmark),
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (game != null)
                      game.displayName
                    else if (gameName.isNotEmpty)
                      gameName,
                    if (displayName != null && displayName.isNotEmpty)
                      displayName,
                  ].join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Text(
                  _relativeTime(bookmark.sortKey),
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton(
                      onPressed: onJoin,
                      child: const Text('加入房间'),
                    ),
                    TextButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('分享'),
                    ),
                    TextButton.icon(
                      onPressed: onShortcut,
                      icon: const Icon(Icons.shortcut_rounded, size: 16),
                      label: const Text('快捷方式'),
                    ),
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('编辑'),
                    ),
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: Icon(Icons.delete_outline,
                          size: 16, color: palette.error),
                      label: Text('删除',
                          style: TextStyle(color: palette.error)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackGameCover extends StatelessWidget {
  const _FallbackGameCover({required this.bookmark});
  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: palette.accentMuted,
        border: Border.all(color: palette.divider.withValues(alpha: 0.5)),
      ),
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

// ============ 编辑 Dialog ============

class _EditResult {
  _EditResult({
    required this.customName,
    required this.pinned,
  });
  final String customName;
  final bool pinned;
}

class _BookmarkEditDialog extends StatefulWidget {
  const _BookmarkEditDialog({required this.bookmark});
  final Bookmark bookmark;

  @override
  State<_BookmarkEditDialog> createState() => _BookmarkEditDialogState();
}

class _BookmarkEditDialogState extends State<_BookmarkEditDialog> {
  late final TextEditingController _name;
  late bool _pinned;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.bookmark.customName);
    _pinned = widget.bookmark.pinned;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑收藏'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名字',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (_) => _submit(context),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
              title: const Text('置顶'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : () => _submit(context),
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _submit(BuildContext c) {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(c, _EditResult(customName: name, pinned: _pinned));
  }
}

// ============ 轻量工具（无 intl 依赖，够用即可）============

String _relativeTime(DateTime dt) {
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

/// 弹「新增 / 编辑收藏」Dialog：供外部组件（Join Dialog / Dashboard）复用。
///
/// - 传入 [existing] = 已有收藏 → 编辑 Dialog 样式
/// - 不传 [existing] + 提供 [proposed] → 新建 Dialog 样式
Future<Bookmark?> showBookmarkEditSheet(
  BuildContext context, {
  required RoomInvitePayload payload,
  Bookmark? existing,
  String? originalShortCode,
  String? originalOfflineToken,
}) async {
  await getIt<GameAssistRulesService>().ensureLoaded();
  if (!context.mounted) return null;
  final defaultName = existing?.customName ??
      (payload.gameName.trim().isNotEmpty
          ? payload.gameName.trim()
          : (payload.displayName?.trim().isNotEmpty == true
              ? payload.displayName!.trim()
              : payload.networkName));
  final result = await showDialog<_EditResult>(
    context: context,
    builder: (c) => _BookmarkCreateDialog(
      defaultName: defaultName,
      defaultPinned: existing?.pinned ?? false,
    ),
  );
  if (result == null) return null;
  final now = DateTime.now();
  return Bookmark(
    id: existing?.id ?? now.millisecondsSinceEpoch,
    customName: result.customName,
    payload: payload,
    originalShortCode:
        originalShortCode ?? existing?.originalShortCode,
    originalOfflineToken:
        originalOfflineToken ?? existing?.originalOfflineToken,
    savedAt: existing?.savedAt ?? now,
    lastUsedAt: existing?.lastUsedAt,
    pinned: result.pinned,
  );
}

class _BookmarkCreateDialog extends StatefulWidget {
  const _BookmarkCreateDialog({
    required this.defaultName,
    required this.defaultPinned,
  });

  final String defaultName;
  final bool defaultPinned;

  @override
  State<_BookmarkCreateDialog> createState() => _BookmarkCreateDialogState();
}

class _BookmarkCreateDialogState extends State<_BookmarkCreateDialog> {
  late final TextEditingController _name;
  late bool _pinned;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.defaultName);
    _pinned = widget.defaultPinned;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('保存房间到收藏'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名字',
                border: OutlineInputBorder(),
                helperText: '给这个房间起个好记的名字，比如「周六星露谷局」',
              ),
              autofocus: true,
              onSubmitted: (_) => _submit(context),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
              title: const Text('置顶'),
              subtitle: const Text('显示在「收藏」列表最前面'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : () => _submit(context),
          child: const Text('加入收藏'),
        ),
      ],
    );
  }

  void _submit(BuildContext c) {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(c, _EditResult(customName: name, pinned: _pinned));
  }
}
