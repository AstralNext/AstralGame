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
    if (session == null || !session.isHost) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('仅房主可分享邀请')),
        );
      }
      return;
    }

    var url = _connectionService.currentJoinShareUrl() ?? '';
    var refreshing = false;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final hasUrl = url.isNotEmpty;
            final token = hasUrl ? extractJoinToken(url) : null;
            final viaShort = token != null && looksLikeShortCode(token);
            return AlertDialog(
              title: const Text('分享房间'),
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
                      hasUrl ? url : '（还没有邀请）',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: refreshing
                      ? null
                      : () async {
                          setState(() => refreshing = true);
                          try {
                            await _connectionService.refreshShareInvite();
                            url = _connectionService.currentJoinShareUrl() ?? '';
                            if (context.mounted) setState(() {});
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(content: Text('$e')),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setState(() => refreshing = false);
                            }
                          }
                        },
                  child: refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('刷新'),
                ),
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
          },
        );
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

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出房间'),
        content: const Text(
          '离开房间：作废短码，房间结束。\n'
          '暂时退出：可稍后「重新开启」同一房间；客人需用新短码重进。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'pause'),
            child: const Text('暂时退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'leave'),
            child: const Text('离开房间'),
          ),
        ],
      ),
    );
    if (choice == 'leave') {
      await _connectionService.leaveRoom();
    } else if (choice == 'pause') {
      await _connectionService.pauseHostRoom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已暂时退出，可在首页重新开启房间')),
        );
      }
    }
  }

  Future<void> _handleResumeHost() async {
    if (_connectionService.isConnecting) return;
    try {
      final session = await _connectionService.resumeHostRoom();
      if (!mounted) return;
      final code = session.shortCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            code == null || code.isEmpty
                ? '房间已恢复，请分享离线邀请给好友'
                : '房间已恢复，请把新短码发给好友：$code',
          ),
        ),
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
    var selected = catalog.first;
    final nameController = TextEditingController();
    final searchController = TextEditingController();
    var query = '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final maxH = MediaQuery.sizeOf(context).height * 0.55;
        return StatefulBuilder(
          builder: (context, setState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? catalog
                : catalog
                    .where((g) =>
                        g.name.toLowerCase().contains(q) ||
                        g.id.toLowerCase().contains(q) ||
                        g.description.toLowerCase().contains(q))
                    .toList(growable: false);
            final selectionValid =
                filtered.any((g) => g.id == selected.id);

            return AlertDialog(
              title: const Text('创建房间'),
              content: SizedBox(
                width: 380,
                height: maxH.clamp(320.0, 480.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: searchController,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: '搜索游戏',
                        hintText: '名称或 id',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        setState(() {
                          query = v;
                          final qq = v.trim().toLowerCase();
                          final list = qq.isEmpty
                              ? catalog
                              : catalog
                                  .where((g) =>
                                      g.name.toLowerCase().contains(qq) ||
                                      g.id.toLowerCase().contains(qq) ||
                                      g.description.toLowerCase().contains(qq))
                                  .toList(growable: false);
                          if (list.isNotEmpty &&
                              !list.any((g) => g.id == selected.id)) {
                            selected = list.first;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '选择游戏',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '没有匹配的游戏',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.tonalIcon(
                                    onPressed: () => _openGameAdaptIssue(
                                      searchController.text,
                                    ),
                                    icon: const Icon(
                                      Icons.open_in_new,
                                      size: 18,
                                    ),
                                    label: const Text('请求适配'),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final g = filtered[index];
                                final selectedNow = selected.id == g.id;
                                return Material(
                                  color: selectedNow
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.55)
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () =>
                                        setState(() => selected = g),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (g.hasGridAsset)
                                            GameGridCover(
                                              game: g,
                                              width: 40,
                                              height: 60,
                                              borderRadius: 8,
                                            )
                                          else
                                            GameLogo(game: g, size: 40),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  g.name,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                if (g.description
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    g.description,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: Theme.of(
                                                                  context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (selectedNow)
                                            Icon(
                                              Icons.check_circle,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '房间备注（可选）',
                        hintText: '例如：周五开黑',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: !selectionValid
                      ? null
                      : () => Navigator.pop(context, true),
                  child: const Text('创建并连接'),
                ),
              ],
            );
          },
        );
      },
    );
    searchController.dispose();
    if (confirmed != true) {
      nameController.dispose();
      return;
    }

    try {
      final session = await _connectionService.createAndConnect(
        gameId: selected.id,
        gameName: selected.name,
        displayName: nameController.text.trim(),
      );
      nameController.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已开房，去分享发给好友')),
      );
    } on ConnectionAbortedException {
      nameController.dispose();
      return;
    } catch (e) {
      nameController.dispose();
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
      builder: (context) => AlertDialog(
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
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, codeController.text.trim()),
            child: const Text('加入'),
          ),
        ],
      ),
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
              onResumeHost: _handleResumeHost,
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
                onResumeHost: _handleResumeHost,
              ),
            );
    });
  }
}
