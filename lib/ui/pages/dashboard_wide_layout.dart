import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/dashboard_home_panel.dart';
import 'package:astral_game/ui/widgets/dashboard_members_skeleton.dart';
import 'package:astral_game/ui/widgets/room_open_games_panel.dart';
import 'package:astral_game/ui/widgets/user_list_widget.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class DashboardWideLayout extends StatelessWidget {
  const DashboardWideLayout({
    super.key,
    required this.nodeManagement,
    required this.screenStateService,
    required this.roomState,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
  });

  final NodeManagementService nodeManagement;
  final ScreenStateService screenStateService;
  final RoomState roomState;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final session = roomState.session.value;
      final showRoom = session != null;

      if (!showRoom) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
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

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: _MembersPane(
              nodeManagement: nodeManagement,
              roomState: roomState,
            ),
          ),
          const SizedBox(width: AppDimensions.sectionGap),
          Expanded(
            flex: 3,
            child: _RoomPane(
              nodeManagement: nodeManagement,
              roomState: roomState,
              onCreateRoom: onCreateRoom,
              onJoinRoom: onJoinRoom,
              onShareRoom: onShareRoom,
              onDisconnect: onDisconnect,
            ),
          ),
        ],
      );
    });
  }
}

class _MembersPane extends StatelessWidget {
  const _MembersPane({
    required this.nodeManagement,
    required this.roomState,
  });

  final NodeManagementService nodeManagement;
  final RoomState roomState;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.divider.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Watch((context) {
              final session = roomState.session.value;
              final game =
                  session == null ? null : GameCatalog.byId(session.gameId);
              final title = [if (game != null) game.displayName, '成员'].join(' · ');
              return Text(
                title,
                style: textTheme.titleSmall?.copyWith(
                  color: palette.accent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              );
            }),
            const SizedBox(height: 12),
            Expanded(
              child: Watch(
                (context) {
                  // 无条件读取，确保 computed 始终订阅成员列表。
                  final nodes = nodeManagement.userNodes.value;
                  if (nodes.isEmpty) {
                    return const DashboardMembersSkeleton();
                  }
                  return UserListWidget(
                    users: nodes,
                    nodeManagement: nodeManagement,
                    physics: const AlwaysScrollableScrollPhysics(),
                    isRoomHostOf: (node) {
                      final s = roomState.session.value;
                      if (s == null) return false;
                      return nodeManagement.isRoomHostPeer(
                        node.peerId,
                        sessionIsHost: s.isHost,
                        isCredentialPeer: node.isCredentialPeer,
                      );
                    },
                  );
                },
                dependencies: [
                  nodeManagement.userNodes,
                  nodeManagement.currentInstanceId,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomPane extends StatelessWidget {
  const _RoomPane({
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
      final linkingFlag = getIt<ConnectionService>().isLinking.value;
      final isLinking =
          roomState.session.value != null && (linkingFlag || !isRunning);
      final myIp = nodeManagement.myVirtualIpv4.value;
      final session = roomState.session.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardHomePanel(
            isConnected: true,
            isLinking: isLinking,
            roomDisplayName: roomState.activeRoomDisplayLabel,
            roomRoleLabel: session?.roleLabel,
            roomGameId: session?.gameId,
            roomShortCode: roomState.activeShareCode,
            isRoomHost: session?.isHost == true,
            hostOnline: roomState.hostOnline.value,
            virtualIp: isRunning
                ? (myIp.isNotEmpty ? myIp : AppConstants.defaultVirtualIp)
                : null,
            onCreateRoom: onCreateRoom,
            onJoinRoom: onJoinRoom,
            onShareRoom: onShareRoom,
            onDisconnect: onDisconnect,
          ),
          const SizedBox(height: AppDimensions.sectionGap),
          Expanded(
            child: isRunning
                ? RoomOpenGamesPanel(
                    gameId: session?.gameId,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    });
  }
}
