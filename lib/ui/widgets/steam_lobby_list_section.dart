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
    GameInfo? game;
    for (final item in catalog) {
      if (item.id == currentId) {
        game = item;
        break;
      }
    }
    setState(() {
      _catalog = catalog;
      _game = game;
    });
    await _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 空 game_id = 「全部」：Rust 侧不加 `ag_game` 过滤，只做本地版本校验。
      final rooms = await widget.connection.steamTransport.searchLobbies(
        _game?.id ?? '',
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
    if (game?.id == _game?.id) return;
    setState(() {
      _game = game;
      _rooms = const [];
      _error = null;
      _loading = true;
    });
    unawaited(_search());
  }

  Future<void> _join(SteamLobbyInfo room) async {
    if (_joiningLobbyId != null || widget.roomActive) return;
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

    // 房间自己的 `ag_game` 才是进房校验用的标识；「全部」筛选下也能正确加入。
    final gameName =
        GameCatalog.byId(room.gameId)?.displayName ??
        (room.gameId.isEmpty ? 'Steam 房间' : room.gameId);

    setState(() => _joiningLobbyId = room.lobbyId);
    try {
      final session = await widget.connection.joinSteamLobby(
        lobbyId: room.lobbyId,
        gameId: room.gameId,
        gameName: gameName,
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
      selectedGame: _game,
      rooms: _rooms,
      loading: _loading,
      error: _error,
      joiningLobbyId: _joiningLobbyId,
      roomActive: widget.roomActive,
      onSelectGame: _loading || _joiningLobbyId != null ? null : _changeGame,
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
    required this.selectedGame,
    required this.rooms,
    required this.loading,
    this.error,
    this.joiningLobbyId,
    this.roomActive = false,
    this.onSelectGame,
    this.onRefresh,
    this.onJoin,
  });

  final List<GameInfo> catalog;

  /// 选中的游戏；null 表示「全部」。
  final GameInfo? selectedGame;

  final List<SteamLobbyInfo> rooms;
  final bool loading;
  final String? error;
  final String? joiningLobbyId;
  final bool roomActive;
  final ValueChanged<GameInfo?>? onSelectGame;
  final VoidCallback? onRefresh;
  final ValueChanged<SteamLobbyInfo>? onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final countText = loading ? '搜索中…' : '${rooms.length} 个房间';
    // 选中态用绿色：浅绿底 + 深一点的绿字（暗色主题下直接用亮绿）。
    final darkSurface = palette.card.computeLuminance() < 0.4;
    final selectedFg = darkSurface
        ? palette.online
        : Color.lerp(palette.online, Colors.black, 0.32)!;
    final selectedBg = palette.online.withValues(
      alpha: darkSurface ? 0.20 : 0.12,
    );

    return AstralCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行：房间数和刷新按钮在右上角。
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.space16,
              2,
              AppDimensions.space8,
              0,
            ),
            child: Row(
              children: [
                Text(
                  '房间列表',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
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
          // 横排游戏标签：一行放不下就横向滚动，不折行。
          _GameFilterBar(
            catalog: catalog,
            selectedGame: selectedGame,
            selectedColor: selectedFg,
            selectedBackground: selectedBg,
            onSelectGame: onSelectGame,
          ),
          Divider(height: 1, thickness: 1, color: palette.divider),
          if (roomActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.space16,
                8,
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
          Expanded(child: _buildBody(context, palette, textTheme)),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppThemePalette palette,
    TextTheme textTheme,
  ) {
    Widget hint(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.space16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(color: palette.textSecondary),
        ),
      ),
    );

    if (loading && rooms.isEmpty) return hint('正在搜索…');
    if (error != null) return hint('搜索失败：$error');
    if (rooms.isEmpty) {
      return hint(selectedGame == null ? '暂无房间' : '该游戏下暂无房间');
    }

    return Scrollbar(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: rooms.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          // 分隔线与房间名左对齐：「全部」多一个 16px 游戏图标。
          indent: selectedGame == null ? 58 : 42,
          endIndent: AppDimensions.space16,
          color: palette.divider,
        ),
        itemBuilder: (context, index) {
          final room = rooms[index];
          return _LobbyRow(
            room: room,
            game: _gameFor(room.gameId),
            // 「全部」下每行需要游戏标识；已按游戏筛选时省掉。
            showGameIcon: selectedGame == null,
            joining: joiningLobbyId == room.lobbyId,
            roomActive: roomActive,
            onJoin: onJoin,
          );
        },
      ),
    );
  }

  /// 房间自己的 `ag_game` 对应的目录项；目录里没有就返回 null。
  GameInfo? _gameFor(String gameId) {
    for (final item in catalog) {
      if (item.id == gameId) return item;
    }
    return GameCatalog.byId(gameId);
  }
}

/// 横排游戏标签栏：放不下时横向滚动，右侧渐隐 + 箭头提示后面还有。
class _GameFilterBar extends StatefulWidget {
  const _GameFilterBar({
    required this.catalog,
    required this.selectedGame,
    required this.selectedColor,
    required this.selectedBackground,
    required this.onSelectGame,
  });

  final List<GameInfo> catalog;
  final GameInfo? selectedGame;
  final Color selectedColor;
  final Color selectedBackground;
  final ValueChanged<GameInfo?>? onSelectGame;

  @override
  State<_GameFilterBar> createState() => _GameFilterBarState();
}

class _GameFilterBarState extends State<_GameFilterBar> {
  final ScrollController _controller = ScrollController();
  bool _moreRight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
  }

  @override
  void didUpdateWidget(covariant _GameFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog.length != widget.catalog.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 右侧还有没滚出来的标签时才显示渐隐和箭头。
  void _syncOverflow() {
    if (!mounted || !_controller.hasClients) return;
    final more = _controller.position.extentAfter > 0.5;
    if (more != _moreRight) setState(() => _moreRight = more);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final selectedGame = widget.selectedGame;
    final onSelectGame = widget.onSelectGame;

    return SizedBox(
      height: 40,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _syncOverflow();
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _syncOverflow();
            return false;
          },
          child: Stack(
            children: [
              ListView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(
                  left: AppDimensions.space12,
                  // 右侧渐隐会盖住尾部，多留一点空间让最后一个标签能完全露出。
                  right: _moreRight ? 40 : AppDimensions.space12,
                ),
                children: [
                  _GameChip(
                    label: '全部',
                    selected: selectedGame == null,
                    selectedColor: widget.selectedColor,
                    selectedBackground: widget.selectedBackground,
                    leading: Icon(
                      Icons.apps_rounded,
                      size: 16,
                      color: selectedGame == null
                          ? widget.selectedColor
                          : palette.textSecondary,
                    ),
                    onTap: onSelectGame == null
                        ? null
                        : () => onSelectGame(null),
                  ),
                  for (final game in widget.catalog)
                    _GameChip(
                      label: game.displayName,
                      selected: selectedGame?.id == game.id,
                      selectedColor: widget.selectedColor,
                      selectedBackground: widget.selectedBackground,
                      leading: _GameChipIcon(game: game),
                      onTap: onSelectGame == null
                          ? null
                          : () => onSelectGame(game),
                    ),
                ],
              ),
              if (_moreRight)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: 48,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            palette.card.withValues(alpha: 0),
                            palette.card,
                          ],
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: palette.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 横排游戏标签：高 32，选中浅绿底 + 绿色文字。
class _GameChip extends StatelessWidget {
  const _GameChip({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.selectedBackground,
    required this.leading,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color selectedBackground;
  final Widget leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppDimensions.radiusSm);
    return Padding(
      padding: const EdgeInsets.only(
        right: AppDimensions.space8,
        top: 4,
        bottom: 4,
      ),
      child: Material(
        color: selected ? selectedBackground : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leading,
                  const SizedBox(width: 6),
                  Text(
                    label,
                    maxLines: 1,
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? selectedColor : palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 游戏头像：有自带图标就用图标，没有就用首字圆底；未知游戏用中性圆底。
class _GameChipIcon extends StatelessWidget {
  const _GameChipIcon({this.game, this.size = 18});

  final GameInfo? game;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final game = this.game;
    if (game == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.textTertiary.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.videogame_asset_outlined,
          size: size * 0.62,
          color: palette.textTertiary,
        ),
      );
    }

    Widget fallback(BuildContext context, Object error, StackTrace? stack) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: game.color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Text(
          game.displayName.isEmpty ? '?' : game.displayName.substring(0, 1),
          style: TextStyle(
            fontSize: size * 0.5,
            height: 1,
            fontWeight: FontWeight.w700,
            color: game.color,
          ),
        ),
      );
    }

    if (!game.hasIconAsset) return fallback(context, '', null);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: GameMediaImage(
          source: game.resolvedIconAsset,
          width: size,
          height: size,
          errorBuilder: fallback,
        ),
      ),
    );
  }
}

class _LobbyRow extends StatelessWidget {
  const _LobbyRow({
    required this.room,
    required this.joining,
    required this.roomActive,
    required this.onJoin,
    this.game,
    this.showGameIcon = false,
  });

  final SteamLobbyInfo room;

  /// 房间所属游戏；仅「全部」语境下展示。
  final GameInfo? game;
  final bool showGameIcon;
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
    final unavailable = tone == AstralStatusTone.unavailable || !_canJoin(room);
    final enabled = !unavailable && !roomActive && !joining;
    // 点位已经表达状态，按钮只保留禁用态；文字解释放到 hover 提示里。
    final blockReason = switch (tone) {
      AstralStatusTone.full => '已满',
      AstralStatusTone.unavailable => '不可加入',
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.space16,
        4,
        AppDimensions.space8,
        4,
      ),
      child: Row(
        children: [
          AstralStatusDot(tone: tone, semanticLabel: _toneLabel(tone)),
          const SizedBox(width: 10),
          // 「全部」混排时补一个游戏标识；已按游戏筛选的行省掉。
          if (showGameIcon) ...[
            _GameChipIcon(game: game, size: 16),
            const SizedBox(width: 8),
          ],
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
          Builder(
            builder: (context) {
              final button = TextButton(
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
                    : const Text('加入'),
              );
              if (blockReason == null) return button;
              return Tooltip(message: blockReason, child: button);
            },
          ),
        ],
      ),
    );
  }
}
