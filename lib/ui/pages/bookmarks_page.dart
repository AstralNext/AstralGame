import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/services/bookmark_cover_store.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/data/state/bookmark_search_state.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/services/shortcut_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/app_toast.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/bookmark_card.dart';
import 'package:astral_game/ui/widgets/bookmark_edit_dialog.dart';
import 'package:astral_game/ui/widgets/confirm_dialog.dart';
import 'package:astral_game/ui/widgets/empty_state.dart';
import 'package:astral_game/ui/widgets/grouped_tile_shape.dart';
import 'package:astral_game/ui/widgets/page_header.dart';
import 'package:astral_game/ui/widgets/page_navigator.dart';
import 'package:astral_game/ui/widgets/section_header.dart';
import 'package:astral_game/utils/error_text.dart';
import 'package:astral_game/utils/room_display.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:astral_game/utils/room_share_actions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 我的收藏（Shell 一级 Tab）。
///
/// - 搜索框：手机点悬浮底栏右侧搜索圆钮展开；桌面/平板在顶栏中央（Shell 注入）
/// - 手机：无限滚动列表；点卡片或长按打开底部操作面板，右侧「加入」直接连接
/// - 宽屏：Steam 游戏墙式网格 + 假分页（每页 [_pageSize] 条）
/// - 操作：加入 / 分享 / 编辑 / 删除 / 置顶 / 封面
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  static const int _pageSize = 20;

  final RoomState _roomState = getIt<RoomState>();
  final ConnectionService _connectionService = getIt<ConnectionService>();
  final ShellNavigationService _shellNav = getIt<ShellNavigationService>();
  final BookmarkSearchState _search = getIt<BookmarkSearchState>();
  EffectCleanup? _queryEffect;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // 搜索词变化时回到第一页
    _queryEffect = effect(() {
      _search.query.value;
      if (mounted) setState(() => _page = 0);
    });
  }

  @override
  void dispose() {
    _queryEffect?.call();
    super.dispose();
  }

  List<Bookmark> _filtered(List<Bookmark> all, String q) {
    if (q.isEmpty) return all;
    return all.where((b) => b.searchHaystack.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.astralPalette.background,
      body: Watch((context) {
        final all = _roomState.bookmarksList.value;
        final q = _search.query.value.trim().toLowerCase();
        final filtered = _filtered(all, q);
        final pinned = filtered.where((b) => b.pinned).toList();
        final unpinned = filtered.where((b) => !b.pinned).toList();
        final isWide =
            MediaQuery.sizeOf(context).width >= AppBreakpoints.narrow;
        final hPad = isWide
            ? AppDimensions.pagePaddingH
            : AppDimensions.pagePaddingHMobile;

        // 假分页只服务宽屏网格；手机端是无限滚动，整份列表一起渲染。
        final totalPages = _totalPages(unpinned.length);
        final pageIndex = _page.clamp(0, totalPages == 0 ? 0 : totalPages - 1);
        final unpinnedSlice = !isWide || unpinned.isEmpty
            ? unpinned
            : unpinned.sublist(
                pageIndex * _pageSize,
                (pageIndex * _pageSize + _pageSize).clamp(0, unpinned.length),
              );

        final isEmpty = all.isEmpty;
        final noResultAfterFilter = all.isNotEmpty && filtered.isEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              horizontalPadding: hPad,
              subtitle: q.isEmpty
                  ? '${all.length} 个房间'
                  : '找到 ${filtered.length} 个房间',
            ),
            Expanded(
              child: isEmpty
                  ? EmptyState(
                      icon: Icons.bookmark_add_outlined,
                      iconSize: 72,
                      title: '还没有收藏的房间',
                      subtitle: '加入或创建房间后，点 ⭐ 即可保存',
                      actionLabel: '去联机页',
                      onAction: _shellNav.openDashboardTab,
                    )
                  : noResultAfterFilter
                  ? EmptyState(
                      icon: Icons.search_off_rounded,
                      title: '没有匹配的收藏',
                      actionLabel: '清空搜索词',
                      actionStyle: EmptyActionStyle.text,
                      onAction: () => _search.clear(),
                    )
                  : _buildBody(
                      isWide: isWide,
                      horizontalPadding: hPad,
                      pinned: pinned,
                      unpinned: unpinned,
                      unpinnedSlice: unpinnedSlice,
                    ),
            ),
            // 分页器只在宽屏出现；手机靠连续滚动，不需要页码。
            if (isWide && !isEmpty && !noResultAfterFilter)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PageNavigator(
                  currentPage: pageIndex,
                  totalPages: totalPages,
                  onPageChanged: (p) => setState(() => _page = p),
                ),
              ),
          ],
        );
      }),
    );
  }

  /// 宽屏：Steam 游戏墙式网格；窄屏：无限滚动的横版卡片列表。
  Widget _buildBody({
    required bool isWide,
    required double horizontalPadding,
    required List<Bookmark> pinned,
    required List<Bookmark> unpinned,
    required List<Bookmark> unpinnedSlice,
  }) {
    Widget card(Bookmark b, {required bool grid}) {
      final actions = BookmarkCardActions(
        onJoin: () => _handleJoin(b),
        onShare: () => _handleShare(b),
        onShortcut: () => _handleShortcut(b),
        onEdit: () => _handleEdit(b),
        onDelete: () => _handleDelete(b),
        onTogglePin: () => _togglePin(b),
        onChangeCover: () => _handleChangeCover(b),
        onRemoveCover: () => _handleRemoveCover(b),
      );
      return grid
          ? BookmarkGridCard(bookmark: b, actions: actions)
          : BookmarkCard(
              bookmark: b,
              actions: actions,
              onOpenActions: () => _showActionsSheet(b),
            );
    }

    if (!isWide) {
      Widget mobileList(List<Bookmark> items) {
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: card(items[i], grid: false),
            ),
          ),
        );
      }

      return CustomScrollView(
        slivers: [
          if (pinned.isNotEmpty) ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                4,
                horizontalPadding,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(title: '置顶', count: pinned.length),
              ),
            ),
            mobileList(pinned),
          ],
          if (unpinned.isNotEmpty) ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                pinned.isEmpty ? 4 : 8,
                horizontalPadding,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(title: '全部收藏', count: unpinned.length),
              ),
            ),
            mobileList(unpinned),
          ],
          // 悬浮胶囊底栏浮在内容上方，末尾留出等高余量避免最后一项被挡住。
          SliverToBoxAdapter(
            child: SizedBox(height: AppDimensions.listBottomWithNav(context)),
          ),
        ],
      );
    }

    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 180,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.74,
    );

    return CustomScrollView(
      slivers: [
        if (pinned.isNotEmpty) ...[
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: SectionHeader(title: '置顶')),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            sliver: SliverGrid(
              gridDelegate: gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, i) => card(pinned[i], grid: true),
                childCount: pinned.length,
              ),
            ),
          ),
        ],
        if (unpinned.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(title: '全部收藏', count: unpinned.length),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            sliver: SliverGrid(
              gridDelegate: gridDelegate,
              delegate: SliverChildBuilderDelegate(
                (context, i) => card(unpinnedSlice[i], grid: true),
                childCount: unpinnedSlice.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  int _totalPages(int length) {
    if (length == 0) return 0;
    return (length / _pageSize).ceil();
  }

  Future<void> _togglePin(Bookmark b) async {
    await _roomState.upsertBookmark(b.copyWith(pinned: !b.pinned));
  }

  /// 手机端操作面板：点卡片 / 长按卡片弹出。
  ///
  /// 手机没有 hover 也没有右键，所以把「加入房间」提升为面板里的主按钮，
  /// 其余低频操作排成整行可点的列表（每项触控高度不小于 48）。
  Future<void> _showActionsSheet(Bookmark b) async {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: palette.background,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        void run(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        return Watch((context) {
          final hasCover = getIt<BookmarkCoverStore>().hasCover(b.id);
          // 有自定义封面时多一项「恢复默认封面」。
          final items =
              <
                ({IconData icon, String label, VoidCallback onTap, bool danger})
              >[
                (
                  icon: b.pinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  label: b.pinned ? '取消置顶' : '置顶',
                  onTap: () => run(() => _togglePin(b)),
                  danger: false,
                ),
                (
                  icon: Icons.share_rounded,
                  label: '分享邀请',
                  onTap: () => run(() => _handleShare(b)),
                  danger: false,
                ),
                (
                  icon: Icons.edit_rounded,
                  label: '编辑名称',
                  onTap: () => run(() => _handleEdit(b)),
                  danger: false,
                ),
                (
                  icon: Icons.image_outlined,
                  label: '更换封面',
                  onTap: () => run(() => _handleChangeCover(b)),
                  danger: false,
                ),
                if (hasCover)
                  (
                    icon: Icons.hide_image_outlined,
                    label: '恢复默认封面',
                    onTap: () => run(() => _handleRemoveCover(b)),
                    danger: false,
                  ),
                (
                  icon: Icons.shortcut_rounded,
                  label: '创建快捷方式',
                  onTap: () => run(() => _handleShortcut(b)),
                  danger: false,
                ),
                (
                  icon: Icons.delete_outline_rounded,
                  label: '删除收藏',
                  onTap: () => run(() => _handleDelete(b)),
                  danger: true,
                ),
              ];

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 72,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: BookmarkCover(bookmark: b),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bookmarkDisplayLabel(b),
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bookmarkGameLabel(b),
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            relativeTime(b.sortKey),
                            style: textTheme.labelSmall?.copyWith(
                              color: palette.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () => run(() => _handleJoin(b)),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('加入房间'),
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.onAccent,
                      textStyle: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AstralCard(
                  padding: EdgeInsets.zero,
                  shadow: false,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        ListTile(
                          shape: groupedTileShape(
                            index: i,
                            count: items.length,
                          ),
                          leading: Icon(
                            items[i].icon,
                            size: 22,
                            color: items[i].danger
                                ? palette.error
                                : palette.accent,
                          ),
                          title: Text(
                            items[i].label,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: items[i].danger
                                  ? palette.error
                                  : palette.textPrimary,
                            ),
                          ),
                          onTap: items[i].onTap,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ============ 操作 ============

  Future<void> _handleJoin(Bookmark b) async {
    if (_connectionService.isConnecting) {
      if (!mounted) return;
      showAppToast(context, '正在连接中，请稍候…');
      return;
    }
    final current = _roomState.session.value;
    if (current != null && current.networkName != b.payload.networkName) {
      final ok = await showConfirmDialog(
        context,
        title: '加入「${b.displayName}」？',
        content:
            '当前已在房间「${current.displayName.isNotEmpty ? current.displayName : current.gameName}」中，'
            '加入新房间会断开你现在的连接。',
        confirmLabel: '断开并加入',
      );
      if (!ok || !mounted) return;
    }
    showAppToast(context, '正在加入「${b.displayName}」…');
    try {
      // 不传 shortCode：_joinWithPayload 会优先复用同房间仍在用的短码
      await _connectionService.joinWithPayload(b.payload);
      // ignore: discarded_futures
      _roomState.touchBookmarkUsed(b.id);
      if (!mounted) return;
      // 连接成功后切回联机页让用户看到"已连接"卡片
      _shellNav.openDashboardTab();
    } on ConnectionAbortedException {
      // 用户主动取消，静默
      return;
    } catch (e) {
      if (!mounted) return;
      final msg = e is ShareCodeException ? e.message : '加入失败：${errorText(e)}';
      showAppToast(context, msg);
    }
  }

  Future<void> _handleShare(Bookmark b) async {
    // 同房间的有效短码优先复用，过期/被作废才会新建，不回写收藏
    String? shareCode;
    try {
      final result = await _connectionService.createShareCodeForPayload(
        b.payload,
      );
      shareCode = result.code;
    } on ShareCodeException catch (e) {
      if (mounted) {
        showAppToast(context, '短码服务暂不可用（${e.message}），改用离线邀请链接');
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '无法生成短码：$e，改用离线邀请链接');
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
    try {
      if (mounted) showAppToast(context, '正在创建快捷方式…');
      final ok = await getIt<ShortcutService>().createDesktopShortcut(
        bookmark: b,
      );
      if (!mounted) return;
      showAppToast(
        context,
        ok
            ? '已创建「${b.displayName}」快捷方式'
            : '快捷方式未创建：请检查系统是否允许 Astral Game 创建桌面快捷方式',
      );
    } on ShortcutException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        ShortcutErrorCode.noPermission => '权限不足：请在系统设置中允许 Astral Game 创建快捷方式',
        ShortcutErrorCode.unsupported => '当前系统不支持桌面快捷方式',
        ShortcutErrorCode.desktopNotFound => '无法定位桌面路径（是否被 OneDrive 重定向？）',
        _ => e.message,
      };
      if (!mounted) return;
      showAppToast(context, msg);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '创建失败：$e');
    }
  }

  Future<void> _handleEdit(Bookmark old) async {
    final next = await showBookmarkEditor(context, existing: old);
    if (next == null || !mounted) return;
    await _roomState.upsertBookmark(next);
    if (mounted) showAppToast(context, '已更新');
  }

  /// 删除收藏：先二次确认，避免误触直接删掉房间。
  ///
  /// 删除成功后不再弹底部提示，避免连续删除时提示反复出现。
  Future<void> _handleDelete(Bookmark b) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除房间？',
      content: '确定要删除「${b.customName}」吗？此操作不可撤销。',
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    await _roomState.removeBookmark(b.id);
  }

  /// 更换封面：选本地图片 → 落盘到支持目录；卡片靠 store.revision 自动刷新。
  Future<void> _handleChangeCover(Bookmark b) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: '选择封面图片',
        type: FileType.image,
        withData: true,
        lockParentWindow: true,
      );
      final file = picked?.files.single;
      if (file == null) return;
      Uint8List? bytes = file.bytes;
      final path = file.path;
      if (bytes == null && path != null) {
        bytes = await File(path).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        if (mounted) showAppToast(context, '读取图片失败');
        return;
      }
      final ok = await getIt<BookmarkCoverStore>().save(b.id, bytes);
      if (!mounted) return;
      showAppToast(context, ok ? '已更新封面' : '保存封面失败');
    } catch (e) {
      if (mounted) showAppToast(context, '选择图片失败：$e');
    }
  }

  /// 移除自定义封面，回到游戏默认封面。
  Future<void> _handleRemoveCover(Bookmark b) async {
    await getIt<BookmarkCoverStore>().remove(b.id);
    if (!mounted) return;
    showAppToast(context, '已恢复默认封面');
  }
}
