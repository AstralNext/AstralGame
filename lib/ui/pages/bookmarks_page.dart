import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:astral_game/ui/widgets/app_snack_bar.dart';
import 'package:astral_game/ui/widgets/bookmark_card.dart';
import 'package:astral_game/ui/widgets/bookmark_edit_dialog.dart';
import 'package:astral_game/ui/widgets/confirm_dialog.dart';
import 'package:astral_game/ui/widgets/empty_state.dart';
import 'package:astral_game/ui/widgets/page_navigator.dart';
import 'package:astral_game/ui/widgets/section_header.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:astral_game/utils/room_share_actions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 我的收藏（Shell 一级 Tab）。
///
/// - 搜索框在顶栏中央（Shell 注入 [BookmarkSearchField]），本页只消费 query
/// - 左侧竖版游戏封面 + 游戏名 + 用户起名
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
        final totalPages = _totalPages(unpinned.length);
        final pageIndex = _page.clamp(0, totalPages == 0 ? 0 : totalPages - 1);
        final unpinnedSlice = unpinned.isEmpty
            ? const <Bookmark>[]
            : unpinned.sublist(
                pageIndex * _pageSize,
                (pageIndex * _pageSize + _pageSize).clamp(0, unpinned.length),
              );
        final isEmpty = all.isEmpty;
        final noResultAfterFilter = all.isNotEmpty && filtered.isEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                      isWide: MediaQuery.sizeOf(context).width >= 600,
                      pinned: pinned,
                      unpinned: unpinned,
                      unpinnedSlice: unpinnedSlice,
                    ),
            ),
            if (!isEmpty && !noResultAfterFilter)
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

  /// 宽屏：Steam 游戏墙式网格；窄屏：一行一个的横版卡片列表。
  Widget _buildBody({
    required bool isWide,
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
          : BookmarkCard(bookmark: b, actions: actions);
    }

    if (!isWide) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          if (pinned.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: SectionHeader(title: '置顶'),
            ),
            for (final b in pinned)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: card(b, grid: false),
              ),
          ],
          if (pinned.isNotEmpty && unpinned.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: SectionHeader(title: '全部收藏'),
            ),
          for (final b in unpinnedSlice)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: card(b, grid: false),
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

  // ============ 操作 ============

  Future<void> _handleJoin(Bookmark b) async {
    if (_connectionService.isConnecting) {
      if (!mounted) return;
      showAppSnackBar(context, '正在连接中，请稍候…');
      return;
    }
    try {
      // 不传 shortCode，让 _joinWithPayload 每次自动 create 新短码
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
      final msg = e is ShareCodeException ? e.message : '加入失败：${e.runtimeType}';
      showAppSnackBar(context, msg);
    }
  }

  Future<void> _handleShare(Bookmark b) async {
    // 每次都 create 新短码（旧码随房主退出早已作废），不回写收藏
    String? shareCode;
    try {
      final result = await _connectionService.createShareCodeForPayload(
        b.payload,
      );
      shareCode = result.code;
    } on ShareCodeException catch (e) {
      if (mounted) {
        showAppSnackBar(context, '短码服务暂不可用（${e.message}），改用离线邀请链接');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, '无法生成短码：$e，改用离线邀请链接');
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
      if (mounted) showAppSnackBar(context, '正在创建快捷方式…');
      final ok = await getIt<ShortcutService>().createDesktopShortcut(
        bookmark: b,
      );
      if (!mounted) return;
      showAppSnackBar(context, ok ? '已创建「${b.displayName}」快捷方式' : '快捷方式未创建');
    } on ShortcutException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        ShortcutErrorCode.noPermission => '权限不足：请在系统设置中允许 Astral Game 创建快捷方式',
        ShortcutErrorCode.unsupported => '当前系统不支持桌面快捷方式',
        ShortcutErrorCode.desktopNotFound => '无法定位桌面路径（是否被 OneDrive 重定向？）',
        _ => e.message,
      };
      if (!mounted) return;
      showAppSnackBar(context, msg);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, '创建失败：$e');
    }
  }

  Future<void> _handleEdit(Bookmark old) async {
    final next = await showBookmarkEditor(context, existing: old);
    if (next == null || !mounted) return;
    await _roomState.upsertBookmark(next);
    if (mounted) showAppSnackBar(context, '已更新');
  }

  /// 删除收藏：先二次确认，避免误触直接删掉房间。
  ///
  /// 刻意不弹底部提示：桌面端 SnackBar 在鼠标悬停时会一直挂着（悬停会取消自动关闭），
  /// 挡在页面上很碍事，所以这里删完即止（撤销入口一并去掉）。
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
        if (mounted) showAppSnackBar(context, '读取图片失败');
        return;
      }
      final ok = await getIt<BookmarkCoverStore>().save(b.id, bytes);
      if (!mounted) return;
      showAppSnackBar(context, ok ? '已更新封面' : '保存封面失败');
    } catch (e) {
      if (mounted) showAppSnackBar(context, '选择图片失败：$e');
    }
  }

  /// 移除自定义封面，回到游戏默认封面。
  Future<void> _handleRemoveCover(Bookmark b) async {
    await getIt<BookmarkCoverStore>().remove(b.id);
    if (!mounted) return;
    showAppSnackBar(context, '已恢复默认封面');
  }
}
