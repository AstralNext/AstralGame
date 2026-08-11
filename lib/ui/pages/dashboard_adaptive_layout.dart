import 'dart:ui';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/pages/dashboard_user_item.dart';
import 'package:astral_game/ui/widgets/dashboard_list_section.dart';
import 'package:astral_game/ui/widgets/glass_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

/// 自适应房间页：Steam 库式网格 / 已连英雄+成员；渐变毛玻璃底。
class DashboardAdaptiveLayout extends StatelessWidget {
  const DashboardAdaptiveLayout({
    super.key,
    required this.nodeManagement,
    required this.roomState,
    required this.onCreateRoom,
    required this.onCreateWithGame,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
  });

  final NodeManagementService nodeManagement;
  final RoomState roomState;
  final VoidCallback onCreateRoom;
  final ValueChanged<GameInfo> onCreateWithGame;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final connected = nodeManagement.isRunning;
      final session = roomState.session.value;
      final game = session == null ? null : GameCatalog.byId(session.gameId);
      final myIp = nodeManagement.myVirtualIpv4.value;
      final virtualIp =
          myIp.isNotEmpty ? myIp : AppConstants.defaultVirtualIp;

      return RoomAtmosphere(
        accent: game?.color,
        child: connected
            ? _ConnectedLibrary(
                game: game,
                roomDisplayName: roomState.activeRoomDisplayLabel ?? '房间',
                roomRoleLabel: session?.roleLabel,
                roomShortCode: roomState.activeShareCode,
                virtualIp: virtualIp,
                isRoomHost: session?.isHost == true,
                nodes: nodeManagement.userNodes.value,
                nodeManagement: nodeManagement,
                roomState: roomState,
                onShare: onShareRoom,
                onDisconnect: onDisconnect,
              )
            : _SteamLibraryIdle(
                onCreateRoom: onCreateRoom,
                onCreateWithGame: onCreateWithGame,
                onJoinRoom: onJoinRoom,
              ),
      );
    });
  }
}

class _SteamLibraryIdle extends StatelessWidget {
  const _SteamLibraryIdle({
    required this.onCreateRoom,
    required this.onCreateWithGame,
    required this.onJoinRoom,
  });

  final VoidCallback onCreateRoom;
  final ValueChanged<GameInfo> onCreateWithGame;
  final VoidCallback onJoinRoom;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    return Watch((context) {
      getIt<GameAssistRulesService>().catalogRevision.value;
      final games =
          GameCatalog.pickerItems.where((g) => g.id != 'other').toList();

      return SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cross = w >= 1100
                ? 5
                : w >= 900
                    ? 4
                    : w >= 600
                        ? 3
                        : 2;
            final pad = w < 600 ? 16.0 : 24.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 12, pad, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '游戏库',
                              style: textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              games.isEmpty
                                  ? '正在加载游戏目录…'
                                  : '点封面开房，或加入好友房间',
                              style: textTheme.bodyMedium?.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: onJoinRoom,
                        child: const Text('加入'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: games.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : GridView.builder(
                          padding: EdgeInsets.fromLTRB(pad, 8, pad, 100),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cross,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            childAspectRatio: 2 / 3,
                          ),
                          itemCount: games.length + 1,
                          itemBuilder: (context, i) {
                            if (i == games.length) {
                              return _LibraryOtherTile(onTap: onCreateRoom);
                            }
                            final g = games[i];
                            return _LibraryCoverTile(
                              game: g,
                              onTap: () => onCreateWithGame(g),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      );
    });
  }
}

class _LibraryCoverTile extends StatefulWidget {
  const _LibraryCoverTile({required this.game, required this.onTap});

  final GameInfo game;
  final VoidCallback onTap;

  @override
  State<_LibraryCoverTile> createState() => _LibraryCoverTileState();
}

class _LibraryCoverTileState extends State<_LibraryCoverTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final g = widget.game;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.03 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadowSoft.withValues(alpha: _hover ? 0.55 : 0.35),
                    blurRadius: _hover ? 28 : 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (g.hasGridAsset)
                      GameMediaImage(
                        source: g.gridAsset!,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => _fallback(g),
                      )
                    else
                      _fallback(g),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.72),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 28, 10, 10),
                          child: Text(
                            g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback(GameInfo g) {
    return ColoredBox(
      color: g.color.withValues(alpha: 0.35),
      child: Center(child: GameLogo(game: g, size: 56)),
    );
  }
}

class _LibraryOtherTile extends StatelessWidget {
  const _LibraryOtherTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: palette.divider.withValues(alpha: 0.7),
              width: 1.5,
            ),
            color: palette.card.withValues(alpha: 0.35),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 36, color: palette.textSecondary),
              const SizedBox(height: 8),
              Text(
                '其他游戏',
                style: TextStyle(
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectedLibrary extends StatelessWidget {
  const _ConnectedLibrary({
    required this.game,
    required this.roomDisplayName,
    this.roomRoleLabel,
    this.roomShortCode,
    required this.virtualIp,
    required this.isRoomHost,
    required this.nodes,
    required this.nodeManagement,
    required this.roomState,
    required this.onShare,
    required this.onDisconnect,
  });

  final GameInfo? game;
  final String roomDisplayName;
  final String? roomRoleLabel;
  final String? roomShortCode;
  final String virtualIp;
  final bool isRoomHost;
  final List<EnhancedNodeInfo> nodes;
  final NodeManagementService nodeManagement;
  final RoomState roomState;
  final VoidCallback onShare;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final code = roomShortCode?.trim() ?? '';
    final meta = [
      if (roomRoleLabel != null && roomRoleLabel!.isNotEmpty) roomRoleLabel!,
      if (virtualIp.isNotEmpty) virtualIp,
    ].join(' · ');

    return Stack(
      fit: StackFit.expand,
      children: [
        if (game != null && game!.hasGridAsset)
          Positioned.fill(
              child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: GameMediaImage(
                source: game!.gridAsset!,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => const SizedBox.shrink(),
              ),
            ),
          ),
        if (game != null && game!.hasGridAsset)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),
        SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final pad = constraints.maxWidth < 600 ? 12.0 : 20.0;

              final roomPane = _RoomHeroGlass(
                game: game,
                roomDisplayName: roomDisplayName,
                meta: meta,
                code: code,
                isRoomHost: isRoomHost,
                onShare: onShare,
                onDisconnect: onDisconnect,
              );

              final membersPane = _MembersGlass(
                game: game,
                nodes: nodes,
                nodeManagement: nodeManagement,
                roomState: roomState,
              );

              if (wide) {
                return Padding(
                  padding: EdgeInsets.all(pad),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth * 0.34).clamp(240.0, 340.0),
                        child: roomPane,
                      ),
                      SizedBox(width: pad),
                      Expanded(child: membersPane),
                    ],
                  ),
                );
              }

              return ListView(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 24),
                children: [
                  roomPane,
                  SizedBox(height: pad),
                  SizedBox(
                    height: 320,
                    child: membersPane,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RoomHeroGlass extends StatelessWidget {
  const _RoomHeroGlass({
    required this.game,
    required this.roomDisplayName,
    required this.meta,
    required this.code,
    required this.isRoomHost,
    required this.onShare,
    required this.onDisconnect,
  });

  final GameInfo? game;
  final String roomDisplayName;
  final String meta;
  final String code;
  final bool isRoomHost;
  final VoidCallback onShare;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    return GlassPanel(
      opacity: 0.42,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (game != null && game!.hasGridAsset)
                    GameMediaImage(
                      source: game!.gridAsset!,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => ColoredBox(
                        color: game!.color.withValues(alpha: 0.3),
                      ),
                    )
                  else
                    ColoredBox(
                      color: (game?.color ?? palette.accent)
                          .withValues(alpha: 0.25),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 100,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.65),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roomDisplayName,
                          style: textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            meta,
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (code.isNotEmpty)
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已复制：$code')),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Text(
                          code,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.5,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.copy_rounded,
                            size: 18, color: palette.textSecondary),
                      ],
                    ),
                  ),
                if (code.isNotEmpty) const SizedBox(height: 12),
                Row(
                  children: [
                    if (isRoomHost) ...[
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: onShare,
                          child: const Text('分享'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDisconnect,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.error,
                          side: BorderSide(
                            color: palette.error.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Text('断开'),
                      ),
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

class _MembersGlass extends StatelessWidget {
  const _MembersGlass({
    required this.game,
    required this.nodes,
    required this.nodeManagement,
    required this.roomState,
  });

  final GameInfo? game;
  final List<EnhancedNodeInfo> nodes;
  final NodeManagementService nodeManagement;
  final RoomState roomState;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final title = [if (game != null) game!.name, '成员'].join(' · ');
    final session = roomState.session.value;

    return GlassPanel(
      opacity: 0.5,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: nodes.isEmpty
                ? const DashboardListEmptyHint(
                    icon: Icons.people_outline,
                    message: '等待好友加入…',
                  )
                : ListView.separated(
                    itemCount: nodes.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: palette.divider.withValues(alpha: 0.35),
                    ),
                    itemBuilder: (context, i) {
                      final node = nodes[i];
                      return DashboardUserItem(
                        key: ValueKey(node.peerId),
                        node: node,
                        compact: true,
                        grouped: false,
                        isRoomHost: session != null &&
                            nodeManagement.isRoomHostPeer(
                              node.peerId,
                              sessionIsHost: session.isHost,
                              isCredentialPeer: node.isCredentialPeer,
                            ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
