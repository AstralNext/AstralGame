import 'dart:async';

import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/pages/bookmarks_page.dart';
import 'package:astral_game/ui/pages/dashboard_narrow_layout.dart';
import 'package:astral_game/ui/pages/dashboard_wide_layout.dart';
import 'package:astral_game/ui/widgets/create_room_dialog.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:astral_game/utils/room_share_actions.dart';
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未连接房间，无法分享邀请')),
        );
      }
      return;
    }

    // 每次 create 新短码（旧的可能过期了），存回 session 复用
    String? shareCode;
    try {
      final result =
          await _connectionService.createShareCodeForCurrentSession();
      shareCode = result.code;
      final updated = session.copyWithNullable(shortCode: result.code);
      _roomState.setSession(updated);
      // 同时回写到匹配的收藏
      final payload = _connectionService.payloadFromCurrentSession();
      if (payload != null) {
        unawaited(_roomState.refreshBookmarkShareCode(
          payload,
          shortCode: result.code,
          adminToken: result.adminToken,
        ));
      }
    } on ShareCodeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('短码服务暂不可用（${e.message}）'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('无法生成短码：$e'),
        ));
      }
    }

    if (!mounted) return;

    final payload = _connectionService.payloadFromCurrentSession();
    final offlineInvite =
        payload != null ? encodeOfflineInvite(payload) : null;
    final url = buildJoinShareUrl(
      shortCode: shareCode,
      offlineInvite: offlineInvite,
    );
    final hasUrl = url.isNotEmpty;
    final token = hasUrl ? extractJoinToken(url) : null;
    final viaShort = token != null && looksLikeShortCode(token);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Watch((_) {
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('分享房间')),
                IconButton(
                  tooltip: '⭐ 收藏当前房间',
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _handleBookmarkRoom();
                  },
                  icon: Icon(
                    Icons.bookmark_border_rounded,
                    color: Theme.of(dialogContext).colorScheme.primary,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    viaShort
                        ? '发给好友这条链接即可加入。短码服务不可用时会自动改用离线链接。'
                        : '短码服务不可用，已生成离线邀请链接。好友点开即可加入。',
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    hasUrl ? url : '（无法生成邀请）',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: !hasUrl
                    ? null
                    : () async {
                        Navigator.pop(dialogContext);
                        if (!this.context.mounted) return;
                        await shareJoinInvite(
                          context: this.context,
                          url: url,
                          gameName: session.gameName,
                        );
                      },
                child: const Text('分享'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _handleDisconnect() async {
    final session = _roomState.session.value;
    if (session == null) {
      await _connectionService.leaveRoom();
      return;
    }

    if (!session.isHost) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('离开房间？'),
          content: const Text('断开后需重新输入短码才能加入。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('离开'),
            ),
          ],
        ),
      );
      if (leave == true) await _connectionService.leaveRoom();
      return;
    }

    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出房间？'),
        content: const Text('离开房间：作废短码，房间结束。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('离开房间'),
          ),
        ],
      ),
    );
    if (leave == true) {
      await _connectionService.leaveRoom();
    }
  }

  Future<void> _handleBookmarkRoom() async {
    final payload = _connectionService.payloadFromCurrentSession();
    final existing = _roomState.findBookmarkForCurrentSession(payload: payload);
    if (existing != null) {
      // 已收藏 → 点击取消
      final removed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('取消收藏？'),
          content: Text('将「${existing.customName}」从收藏中移除'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('再想想'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('取消收藏'),
            ),
          ],
        ),
      );
      if (removed == true && mounted) {
        await _roomState.removeBookmark(existing.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已从收藏中移除')),
        );
      }
      return;
    }
    // 未收藏 → 打开编辑 Sheet
    if (payload == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有可收藏的房间配置')),
        );
      }
      return;
    }
    if (!mounted) return;
    final session = _roomState.session.value;
    final bookmark = await showBookmarkEditSheet(
      context,
      payload: payload,
      existing: null,
      originalShortCode: session?.shortCode,
    );
    if (bookmark == null || !mounted) return;
    await _roomState.upsertBookmark(bookmark);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入收藏：${bookmark.customName}')),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('游戏目录未加载')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开房，去分享发给好友')),
      );
    } on ConnectionAbortedException {
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _parseAndBookmark(String raw) async {
    try {
      final resolved = await _connectionService.resolveInvitePayload(raw);
      if (!mounted) return;
      final bookmark = await showBookmarkEditSheet(
        context,
        payload: resolved.payload,
        existing: null,
        originalShortCode: resolved.shortCode,
        originalOfflineToken: resolved.offlineToken,
      );
      if (bookmark == null || !mounted) return;
      await _roomState.upsertBookmark(bookmark);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加入收藏：${bookmark.customName}')),
      );
    } on ShareCodeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      _consumeForceEndNotice();
      final isNarrow = _screenStateService.isNarrow;
      return isNarrow
          ? DashboardNarrowLayout(
              nodeManagement: _nodeManagement,
              roomState: _roomState,
              onCreateRoom: _handleCreateRoom,
              onJoinRoom: _handleJoinRoom,
              onShareRoom: _handleShareRoom,
              onDisconnect: _handleDisconnect,
              onBookmarkRoom: _handleBookmarkRoom,
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: DashboardWideLayout(
                nodeManagement: _nodeManagement,
                screenStateService: _screenStateService,
                roomState: _roomState,
                onCreateRoom: _handleCreateRoom,
                onJoinRoom: _handleJoinRoom,
                onShareRoom: _handleShareRoom,
                onDisconnect: _handleDisconnect,
                onBookmarkRoom: _handleBookmarkRoom,
              ),
            );
    });
  }
}
