import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/pages/dashboard_narrow_layout.dart';
import 'package:astral_game/ui/pages/dashboard_wide_layout.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals_flutter.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final NodeManagementService _nodeManagement = GetIt.I<NodeManagementService>();
  final ConnectionService _connectionService = GetIt.I<ConnectionService>();
  final ScreenStateService _screenStateService = GetIt.I<ScreenStateService>();
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

    var code = session.shortCode ?? '';
    var offlineInvite = _connectionService.currentOfflineInvite() ?? '';
    var refreshing = false;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final hasShort = code.isNotEmpty;
            final hasOffline = offlineInvite.isNotEmpty;
            return AlertDialog(
              title: const Text('分享房间'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      hasShort
                          ? '优先发 9 位短码；短码服务不可用时用下方离线邀请（AG1.）。刷新会作废旧邀请。'
                          : '短码服务不可用，请复制离线邀请码发给好友（AG1. 开头）。刷新可重试短码。',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '短码',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      hasShort ? code : '（未生成）',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: hasShort ? 4 : 0,
                          ),
                    ),
                    if (hasOffline) ...[
                      const SizedBox(height: 20),
                      Text(
                        '离线邀请',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            offlineInvite,
                            style: TextStyle(
                              fontFamily: 'Consolas',
                              fontFamilyFallback: const [
                                'Courier New',
                                'monospace',
                              ],
                              fontSize: 11,
                              height: 1.35,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
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
                            final r =
                                await _connectionService.refreshShareInvite();
                            code = r.shortCode ?? '';
                            offlineInvite = r.offlineInvite;
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
                if (hasShort && hasOffline)
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: offlineInvite),
                      );
                      if (this.context.mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('离线邀请已复制')),
                        );
                      }
                    },
                    child: const Text('复制离线邀请'),
                  ),
                FilledButton(
                  onPressed: hasShort
                      ? () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: roomShareCodeForClipboard(code),
                            ),
                          );
                          if (this.context.mounted) {
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('短码已复制：$code')),
                            );
                          }
                        }
                      : (hasOffline
                          ? () async {
                              await Clipboard.setData(
                                ClipboardData(text: offlineInvite),
                              );
                              if (this.context.mounted) {
                                Navigator.pop(dialogContext);
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(content: Text('离线邀请已复制')),
                                );
                              }
                            }
                          : null),
                  child: Text(hasShort ? '复制短码' : '复制离线邀请'),
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

  Future<void> _handleCreateRoom() async {
    if (_connectionService.isConnecting) return;
    final catalog = GameCatalog.pickerItems;
    if (catalog.isEmpty) {
      if (!mounted) return;
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
                        g.id.toLowerCase().contains(q))
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
                                      g.id.toLowerCase().contains(qq))
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
                              child: Text(
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
                                            child: Text(
                                              g.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
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
      final code = session.shortCode;
      if (code != null && code.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已开房，短码：$code（可在分享里复制）')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已开房；短码不可用，请在分享里复制离线邀请'),
          ),
        );
      }
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
              labelText: '短码或离线邀请',
              hintText: '9 位数字，或粘贴 AG1. 开头的离线邀请',
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
