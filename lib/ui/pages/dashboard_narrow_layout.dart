import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/open_games_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/pages/dashboard_user_item.dart';
import 'package:astral_game/ui/widgets/dashboard_home_panel.dart';
import 'package:astral_game/ui/widgets/dashboard_members_skeleton.dart';
import 'package:astral_game/ui/widgets/room_open_games_panel.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class DashboardNarrowLayout extends StatelessWidget {
  const DashboardNarrowLayout({
    super.key,
    required this.nodeManagement,
    required this.roomState,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
  });

  final NodeManagementService nodeManagement;
  final RoomState roomState;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final isRunning = nodeManagement.isRunning;
      final session = roomState.session.value;
      final linkingFlag = getIt<ConnectionService>().isLinking.value;
      final showRoom = session != null;
      final isLinking = showRoom && (linkingFlag || !isRunning);

      if (!showRoom) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.pagePaddingH,
            AppDimensions.pagePaddingV,
            AppDimensions.pagePaddingH,
            8,
          ),
          child: DashboardHomePanel(
            isConnected: false,
            username: nodeManagement.currentUsername.value,
            onCreateRoom: onCreateRoom,
            onJoinRoom: onJoinRoom,
            onShareRoom: onShareRoom,
            onDisconnect: onDisconnect,
          ),
        );
      }

      final active = session;
      return CustomScrollView(
        key: const PageStorageKey<String>('dashboard_narrow_scroll'),
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.pagePaddingH,
              AppDimensions.pagePaddingV,
              AppDimensions.pagePaddingH,
              8,
            ),
            sliver: SliverToBoxAdapter(
              child: _NarrowRoomHeader(
                nodeManagement: nodeManagement,
                roomState: roomState,
                isRunning: isRunning,
                isLinking: isLinking,
                username: nodeManagement.currentUsername.value,
                roleLabel: active.roleLabel,
                gameId: active.gameId,
                isHost: active.isHost,
                onCreateRoom: onCreateRoom,
                onJoinRoom: onJoinRoom,
                onShareRoom: onShareRoom,
                onDisconnect: onDisconnect,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.pagePaddingH,
              8,
              AppDimensions.pagePaddingH,
              8,
            ),
            sliver: SliverToBoxAdapter(
              child: _NarrowOpenGamesSlot(
                gameId: active.gameId,
                isRunning: isRunning,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.pagePaddingH,
              8,
              AppDimensions.pagePaddingH,
              28,
            ),
            sliver: _MembersBlock(
              roomState: roomState,
              nodeManagement: nodeManagement,
            ),
          ),
        ],
      );
    });
  }
}

class _NarrowRoomHeader extends StatelessWidget {
  const _NarrowRoomHeader({
    required this.nodeManagement,
    required this.roomState,
    required this.isRunning,
    required this.isLinking,
    required this.username,
    required this.roleLabel,
    required this.gameId,
    required this.isHost,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
  });

  final NodeManagementService nodeManagement;
  final RoomState roomState;
  final bool isRunning;
  final bool isLinking;
  final String username;
  final String? roleLabel;
  final String gameId;
  final bool isHost;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final myIp = nodeManagement.myVirtualIpv4.value;
      return DashboardHomePanel(
        isConnected: true,
        isLinking: isLinking,
        username: username,
        roomDisplayName: roomState.activeRoomDisplayLabel,
        roomRoleLabel: roleLabel,
        roomGameId: gameId,
        roomShortCode: roomState.activeShareCode,
        isRoomHost: isHost,
        hostOnline: roomState.hostOnline.value,
        virtualIp: isRunning
            ? (myIp.isNotEmpty ? myIp : AppConstants.defaultVirtualIp)
            : null,
        onCreateRoom: onCreateRoom,
        onJoinRoom: onJoinRoom,
        onShareRoom: onShareRoom,
        onDisconnect: onDisconnect,
      );
    });
  }
}

class _NarrowOpenGamesSlot extends StatelessWidget {
  const _NarrowOpenGamesSlot({
    required this.gameId,
    required this.isRunning,
  });

  final String gameId;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final openGames = getIt<OpenGamesService>();
      final openListings = openGames.listings.value;
      final showOpenGames =
          isRunning && (openGames.isActive || openListings.isNotEmpty);
      if (!showOpenGames) return const SizedBox.shrink();
      final openGamesHeight = openListings.isEmpty ? 72.0 : 220.0;
      return AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: openGamesHeight,
          width: double.infinity,
          child: RoomOpenGamesPanel(
            compact: true,
            gameId: gameId,
          ),
        ),
      );
    });
  }
}

class _MembersBlock extends StatelessWidget {
  const _MembersBlock({
    required this.roomState,
    required this.nodeManagement,
  });

  final RoomState roomState;
  final NodeManagementService nodeManagement;

  @override
  Widget build(BuildContext context) {
    return Watch(
      (context) {
        final session = roomState.session.value;
        final game = session == null ? null : GameCatalog.byId(session.gameId);
        final title = [
          if (game != null) game.displayName,
          '成员',
        ].join(' · ');
        final nodes = nodeManagement.userNodes.value;
        final theme = Theme.of(context).textTheme;
        final palette = context.astralPalette;

        // 第 0 项：标题行；1..N：用户项。SliverList.builder 懒构建。
        return SliverList.builder(
          itemCount: nodes.isEmpty ? 1 : nodes.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: theme.labelLarge?.copyWith(
                            color: palette.accent,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                        if (nodes.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${nodes.length}',
                            style: theme.labelSmall?.copyWith(
                              color: palette.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (nodes.isEmpty) const DashboardMembersSkeleton(),
                ],
              );
            }

            final i = index - 1;
            final node = nodes[i];
            return Column(
              children: [
                if (i > 0) const Divider(height: 1, indent: 56),
                DashboardUserItem(
                  key: ValueKey<int>(node.peerId),
                  node: node,
                  nodeManagement: nodeManagement,
                  grouped: true,
                  index: i,
                  count: nodes.length,
                  isRoomHost: session != null &&
                      nodeManagement.isRoomHostPeer(
                        node.peerId,
                        sessionIsHost: session.isHost,
                        isCredentialPeer: node.isCredentialPeer,
                      ),
                ),
              ],
            );
          },
        );
      },
      dependencies: [
        nodeManagement.userNodes,
        nodeManagement.currentInstanceId,
      ],
    );
  }
}
