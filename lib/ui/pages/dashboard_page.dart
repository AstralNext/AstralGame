import 'dart:async';

import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/pages/dashboard_narrow_layout.dart';
import 'package:astral_game/ui/pages/dashboard_wide_layout.dart';
import 'package:astral_game/ui/widgets/app_snack_bar.dart';
import 'package:astral_game/ui/widgets/confirm_dialog.dart';
import 'package:astral_game/ui/widgets/create_room_dialog.dart';
import 'package:astral_game/ui/widgets/dashboard_home_panel.dart';
import 'package:astral_game/ui/widgets/share_room_dialog.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final NodeManagementService _nodeManagement = getIt<NodeManagementService>();
  final ConnectionService _connectionService = getIt<ConnectionService>();
  final ScreenStateService _screenStateService = getIt<ScreenStateService>();
  final RoomState _roomState = getIt<RoomState>();

  Future<void> _handleShareRoom() async {
    final session = _roomState.session.value;
    if (session == null) {
      if (mounted) showAppSnackBar(context, '未连接房间，无法分享邀请');
      return;
    }

    // 每次 create 新短码（旧的可能过期了），存回 session 复用
    String? shareCode;
    try {
      final result = await _connectionService
          .createShareCodeForCurrentSession();
      shareCode = result.code;
      final updated = session.copyWithNullable(shortCode: result.code);
      _roomState.setSession(updated);
      // 同时回写到匹配的收藏
      final payload = _connectionService.payloadFromCurrentSession();
      if (payload != null) {
        unawaited(
          _roomState.refreshBookmarkShareCode(
            payload,
            shortCode: result.code,
            adminToken: result.adminToken,
          ),
        );
      }
    } on ShareCodeException catch (e) {
      if (mounted) showAppSnackBar(context, '短码服务暂不可用（${e.message}）');
    } catch (e) {
      if (mounted) showAppSnackBar(context, '无法生成短码：$e');
    }

    if (!mounted) return;

    final payload = _connectionService.payloadFromCurrentSession();
    final offlineInvite = payload != null ? encodeOfflineInvite(payload) : null;
    final url = buildJoinShareUrl(
      shortCode: shareCode,
      offlineInvite: offlineInvite,
    );
    final token = url.isNotEmpty ? extractJoinToken(url) : null;
    final viaShort = token != null && looksLikeShortCode(token);

    await showShareRoomDialog(
      context,
      url: url,
      viaShort: viaShort,
      gameName: session.gameName,
      onBookmark: _handleBookmarkRoom,
    );
  }

  Future<void> _handleDisconnect() async {
    final session = _roomState.session.value;
    if (session == null) {
      await _connectionService.leaveRoom();
      return;
    }

    if (!session.isHost) {
      final leave = await showConfirmDialog(
        context,
        title: '离开房间？',
        content: '断开后需重新输入短码才能加入。',
        confirmLabel: '离开',
      );
      if (leave) await _connectionService.leaveRoom();
      return;
    }

    final leave = await showConfirmDialog(
      context,
      title: '退出房间？',
      content: '离开房间：作废短码，房间结束。',
      confirmLabel: '离开房间',
    );
    if (leave) await _connectionService.leaveRoom();
  }

  Future<void> _handleBookmarkRoom() async {
    final payload = _connectionService.payloadFromCurrentSession();
    final existing = _roomState.findBookmarkForCurrentSession(payload: payload);
    if (existing != null) {
      // 已收藏 → 再点 = 取消收藏，带「撤销」
      await _roomState.removeBookmark(existing.id);
      if (!mounted) return;
      showAppSnackBar(
        context,
        '已从收藏移除：${existing.customName}',
        actionLabel: '撤销',
        onAction: () => _roomState.upsertBookmark(existing),
      );
      return;
    }
    // 未收藏 → 一键收藏，自动命名（重名自动加序号），不弹窗
    if (payload == null) {
      if (mounted) showAppSnackBar(context, '还没有可收藏的房间配置');
      return;
    }
    final session = _roomState.session.value;
    final bookmark = await _roomState.quickSaveBookmark(
      payload,
      originalShortCode: session?.shortCode,
    );
    if (!mounted) return;
    showAppSnackBar(context, '已加入收藏：${bookmark.customName}');
  }

  void _consumeForceEndNotice() {
    final notice = _roomState.forceEndNotice.value;
    if (notice == null || notice.isEmpty) return;
    _roomState.clearForceEndNotice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('已离开房间'),
          content: Text(notice),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _openGameAdaptIssue(String searchedName) async {
    final uri = Uri.parse(AppConstants.githubGameAdaptIssueUrl).replace(
      queryParameters: {
        'template': 'game-adapt.yml',
        if (searchedName.trim().isNotEmpty) 'game_name': searchedName.trim(),
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handleCreateRoom() async {
    if (_connectionService.isConnecting) return;
    await getIt<GameAssistRulesService>().ensureLoaded();
    if (!mounted) return;
    final catalog = GameCatalog.pickerItems;
    if (catalog.isEmpty) {
      showAppSnackBar(context, '游戏目录未加载');
      return;
    }
    final selected = await showCreateRoomDialog(
      context,
      catalog: catalog,
      onRequestAdapt: _openGameAdaptIssue,
    );
    if (selected == null) return;

    try {
      await _connectionService.createAndConnect(
        gameId: selected.id,
        gameName: selected.displayName,
      );
      if (!mounted) return;
      showAppSnackBar(context, '已开房，去分享发给好友');
    } on ConnectionAbortedException {
      return;
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e');
    }
  }

  Future<void> _handleJoinRoom() async {
    if (_connectionService.isConnecting) return;
    final codeController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('加入房间'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: codeController,
              keyboardType: TextInputType.text,
              maxLines: 4,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: '邀请链接 / 短码',
                hintText: '粘贴 next.astral.fan/j 链接，或短码',
                alignLabelWithHint: true,
              ),
              onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton.tonal(
              onPressed: () async {
                final raw = codeController.text.trim();
                if (raw.isEmpty) return;
                Navigator.pop(dialogContext);
                await _parseAndBookmark(raw);
              },
              child: const Text('解析并收藏'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, codeController.text.trim()),
              child: const Text('加入'),
            ),
          ],
        );
      },
    );
    if (result == null || result.isEmpty) return;
    try {
      await _connectionService.joinWithInviteInput(result);
    } on ConnectionAbortedException {
      return;
    } on ShareCodeException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e');
    }
  }

  Future<void> _parseAndBookmark(String raw) async {
    try {
      final resolved = await _connectionService.resolveInvitePayload(raw);
      if (!mounted) return;
      final bookmark = await _roomState.quickSaveBookmark(
        resolved.payload,
        originalShortCode: resolved.shortCode,
        originalOfflineToken: resolved.offlineToken,
      );
      if (!mounted) return;
      showAppSnackBar(context, '已加入收藏：${bookmark.customName}');
    } on ShareCodeException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showAppSnackBar(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      _consumeForceEndNotice();
      final isNarrow = _screenStateService.isNarrow;
      final callbacks = DashboardCallbacks(
        onCreateRoom: _handleCreateRoom,
        onJoinRoom: _handleJoinRoom,
        onShareRoom: _handleShareRoom,
        onDisconnect: _handleDisconnect,
        onBookmarkRoom: _handleBookmarkRoom,
      );
      return isNarrow
          ? DashboardNarrowLayout(
              nodeManagement: _nodeManagement,
              roomState: _roomState,
              callbacks: callbacks,
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: DashboardWideLayout(
                nodeManagement: _nodeManagement,
                screenStateService: _screenStateService,
                roomState: _roomState,
                callbacks: callbacks,
              ),
            );
    });
  }
}
