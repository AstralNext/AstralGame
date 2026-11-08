import 'dart:async';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/src/rust/api/steam.dart';
import 'package:astral_game/ui/widgets/app_toast.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/astral_status_dot.dart';
import 'package:astral_game/ui/widgets/section_header.dart';
import 'package:flutter/material.dart';

/// Steam Tab 内常驻的房间列表。
///
/// 搜索、按游戏隔离与口令校验链保持原样（Rust 侧服务端 `ag_game` 过滤 +
/// 本地二次校验），这里只把原来的弹窗换成页面内区块。
class SteamLobbyListSection extends StatefulWidget {
  const SteamLobbyListSection({
    super.key,
    required this.connection,
    required this.roomActive,
    this.onJoined,
  });

  final ConnectionService connection;

  /// 已在组网房间中时禁用加入，并给一行提示。
  final bool roomActive;

  final VoidCallback? onJoined;

  @override
  SteamLobbyListSectionState createState() => SteamLobbyListSectionState();
}

class SteamLobbyListSectionState extends State<SteamLobbyListSection> {
  List<GameInfo> _catalog = const [];
  GameInfo? _game;
  List<SteamLobbyInfo> _rooms = const [];
  bool _loading = true;
  String? _error;
  String? _joiningLobbyId;
  bool _pageActive = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCatalogAndSearch());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // IndexedStack 里离开 Steam Tab 时 TickerMode 变 false，回来再自动搜一次。
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_pageActive && _catalog.isNotEmpty) {
      unawaited(_search());
    }
    _pageActive = active;
  }

  /// 供邀请弹窗的「去搜索房间」等入口手动刷新。
  Future<void> refresh() async {
    if (_catalog.isEmpty) {
      await _loadCatalogAndSearch();
      return;
    }
    await _search();
  }

  Future<void> _loadCatalogAndSearch() async {
    try {
      await getIt<GameAssistRulesService>().ensureLocalLoaded();
    } catch (_) {
      // 目录加载失败时下面会显示「游戏目录未加载」，刷新按钮可重试。
    }
    if (!mounted) return;
    final catalog = GameCatalog.pickerItems;
    if (catalog.isEmpty) {
      setState(() {
        _catalog = catalog;
        _rooms = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    final currentId = _game?.id;
    final game = currentId == null
        ? catalog.first
        : catalog.firstWhere(
            (item) => item.id == currentId,
            orElse: () => catalog.first,
          );
    setState(() {
      _catalog = catalog;
      _game = game;
    });
    await _search();
  }

  Future<void> _search() async {
    final game = _game;
    if (game == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rooms = await widget.connection.steamTransport.searchLobbies(
        game.id,
      );
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _changeGame(GameInfo? game) {
    if (game == null || game.id == _game?.id) return;
    setState(() {
      _game = game;
      _rooms = const [];
      _error = null;
      _loading = true;
    });
    unawaited(_search());
  }

  Future<void> _join(SteamLobbyInfo room) async {
    final game = _game;
    if (game == null || _joiningLobbyId != null || widget.roomActive) return;
    if (!_LobbyRow._canJoin(room)) return;

    String? extra;
    if (room.gate == kSteamLobbyGateDouble) {
      extra = await _askExtraPassword(room);
      if (extra == null) return;
    } else if (room.gate == kSteamLobbyGateOpen) {
      final confirmed = await _confirmOpen(room);
      if (confirmed != true) return;
    }
    if (!mounted) return;

    setState(() => _joiningLobbyId = room.lobbyId);
    try {
      final session = await widget.connection.joinSteamLobby(
        lobbyId: room.lobbyId,
        gameId: game.id,
        gameName: game.displayName,
        extraPassword: extra,
      );
      if (!mounted) return;
      showAppToast(context, '已加入「${session.gameName}」房间');
      widget.onJoined?.call();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '$e');
    } finally {
      if (mounted) setState(() => _joiningLobbyId = null);
    }
    if (mounted) await _search();
  }

  Future<String?> _askExtraPassword(SteamLobbyInfo room) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierColor: astralDialogBarrierColor,
      builder: (dialogContext) => AlertDialog(
        title: const Text('输入房间密码'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: '额外密码'),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('加入'),
          ),
        ],
      ),
    ).then((value) => (value == null || value.isEmpty) ? null : value);
  }

  Future<bool?> _confirmOpen(SteamLobbyInfo room) {
    return showDialog<bool>(
      context: context,
      barrierColor: astralDialogBarrierColor,
      builder: (dialogContext) => AlertDialog(
        title: const Text('加入完全公开的房间？'),
        content: Text(
          '「${room.name}」没有设置额外密码，任何人搜到都能进来。'
          '如果不是你认识的房主，建议先确认再进。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SteamLobbyListView(
      catalog: _catalog,
      game: _game,
      rooms: _rooms,
      loading: _loading,
      error: _error,
      joiningLobbyId: _joiningLobbyId,
      roomActive: widget.roomActive,
      onGameChanged: _loading || _joiningLobbyId != null ? null : _changeGame,
      onRefresh: _loading ? null : () => unawaited(refresh()),
      onJoin: (room) => unawaited(_join(room)),
    );
  }
}

/// 纯展示层：三张验收截图直接渲染这一个组件。
class SteamLobbyListView extends StatelessWidget {
  const SteamLobbyListView({
    super.key,
    required this.catalog,
    required this.game,
    required this.rooms,
    required this.loading,
    this.error,
    this.joiningLobbyId,
    this.roomActive = false,
    this.onGameChanged,
    this.onRefresh,
    this.onJoin,
  });

  final List<GameInfo> catalog;
  final GameInfo? game;
  final List<SteamLobbyInfo> rooms;
  final bool loading;
  final String? error;
  final String? joiningLobbyId;
  final bool roomActive;
  final ValueChanged<GameInfo?>? onGameChanged;
  final VoidCallback? onRefresh;
  final ValueChanged<SteamLobbyInfo>? onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    Widget hint(String text) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.space16,
        vertical: 18,
      ),
      child: Text(
        text,
        style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
      ),
    );

    final countText = loading && rooms.isEmpty ? '搜索中…' : '${rooms.length} 个房间';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '房间列表', tone: SectionHeaderTone.muted),
        AstralCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.space16,
                  1,
                  AppDimensions.space8,
                  1,
                ),
                child: Row(
                  children: [
                    if (catalog.isNotEmpty && game != null)
                      DropdownButtonHideUnderline(
                        child: DropdownButton<GameInfo>(
                          value: game,
                          isDense: true,
                          iconSize: 18,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusSm,
                          ),
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                          items: [
                            for (final item in catalog)
                              DropdownMenuItem(
                                value: item,
                                child: Text(item.displayName),
                              ),
                          ],
                          onChanged: onGameChanged,
                        ),
                      )
                    else
                      Text(
                        '游戏目录未加载',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: palette.textSecondary,
                        ),
                      ),
                    const Spacer(),
                    Text(
                      countText,
                      style: textTheme.bodySmall?.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.space4),
                    IconButton(
                      tooltip: '刷新房间列表',
                      visualDensity: VisualDensity.compact,
                      onPressed: loading ? null : onRefresh,
                      icon: loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.refresh_rounded,
                              size: 20,
                              color: palette.textSecondary,
                            ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: palette.divider),
              if (roomActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimensions.space16,
                    10,
                    AppDimensions.space16,
                    0,
                  ),
                  child: Text(
                    '已在组网房间中，离开后可加入其他房间',
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              if (loading && rooms.isEmpty)
                hint('正在搜索…')
              else if (error != null)
                hint('搜索失败：$error')
              else if (rooms.isEmpty)
                hint('同游戏下暂无房间')
              else
                for (var index = 0; index < rooms.length; index++) ...[
                  _LobbyRow(
                    room: rooms[index],
                    joining: joiningLobbyId == rooms[index].lobbyId,
                    roomActive: roomActive,
                    onJoin: onJoin,
                  ),
                  if (index != rooms.length - 1)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 42,
                      endIndent: AppDimensions.space16,
                      color: palette.divider,
                    ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LobbyRow extends StatelessWidget {
  const _LobbyRow({
    required this.room,
    required this.joining,
    required this.roomActive,
    required this.onJoin,
  });

  final SteamLobbyInfo room;
  final bool joining;
  final bool roomActive;
  final ValueChanged<SteamLobbyInfo>? onJoin;

  static bool _canJoin(SteamLobbyInfo room) =>
      room.joinable &&
      room.version == kSteamLobbyProtocolVersion &&
      (room.capacity <= 0 || room.players < room.capacity);

  static AstralStatusTone _tone(SteamLobbyInfo room) {
    if (!room.joinable || room.version != kSteamLobbyProtocolVersion) {
      return AstralStatusTone.unavailable;
    }
    if (room.capacity > 0 && room.players >= room.capacity) {
      return AstralStatusTone.full;
    }
    if (room.gate == kSteamLobbyGateDouble) {
      return AstralStatusTone.secured;
    }
    return AstralStatusTone.ready;
  }

  static String _toneLabel(AstralStatusTone tone) {
    return switch (tone) {
      AstralStatusTone.ready => '可加入',
      AstralStatusTone.secured => '需要口令',
      AstralStatusTone.full => '满员',
      AstralStatusTone.unavailable => '不可加入',
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final tone = _tone(room);
    final full = tone == AstralStatusTone.full;
    final unavailable = tone == AstralStatusTone.unavailable || !_canJoin(room);
    final enabled = !unavailable && !roomActive && !joining;
    final label = full ? '已满' : (unavailable ? '不可加入' : '加入');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.space16,
        6,
        AppDimensions.space8,
        6,
      ),
      child: Row(
        children: [
          AstralStatusDot(tone: tone, semanticLabel: _toneLabel(tone)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              room.name.isEmpty ? '未命名房间' : room.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${room.players}/${room.capacity}',
            style: textTheme.labelMedium?.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Tooltip(
            message: 'Steam 搜索不返回延迟，进房后显示',
            child: SizedBox(
              width: 36,
              child: Text(
                '—',
                textAlign: TextAlign.right,
                style: textTheme.labelMedium?.copyWith(
                  color: palette.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: enabled ? () => onJoin?.call(room) : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child: joining
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(label),
          ),
        ],
      ),
    );
  }
}
