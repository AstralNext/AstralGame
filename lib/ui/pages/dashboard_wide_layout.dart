import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/ui/widgets/dashboard_home_panel.dart';
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
    this.onResumeHost,
  });

  final NodeManagementService nodeManagement;
  final ScreenStateService screenStateService;
  final RoomState roomState;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;
  final VoidCallback? onResumeHost;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final connected = nodeManagement.isRunning;
      final paused = roomState.pausedHost.value;
      if (!connected) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          child: DashboardHomePanel(
            isConnected: false,
            username: nodeManagement.currentUsername.value,
            pausedRoomName: paused?.displayName,
            onCreateRoom: onCreateRoom,
            onJoinRoom: onJoinRoom,
            onShareRoom: onShareRoom,
            onDisconnect: onDisconnect,
            onResumeHost: onResumeHost,
          ),
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 6, child: _buildMembersPane(context)),
          const SizedBox(width: AppDimensions.sectionGap),
          Expanded(flex: 3, child: _buildRoomPane(context)),
        ],
      );
    });
  }

  Widget _buildMembersPane(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final session = roomState.session.value;
    final game = session == null ? null : GameCatalog.byId(session.gameId);
    final title = [if (game != null) game.name, '成员'].join(' · ');

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
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                color: palette.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: UserListWidget(
                users: nodeManagement.userNodes.value,
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomPane(BuildContext context) {
    return Watch((context) {
      final myIp = nodeManagement.myVirtualIpv4.value;
      final session = roomState.session.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardHomePanel(
            isConnected: true,
            roomDisplayName: roomState.activeRoomDisplayLabel,
            roomRoleLabel: session?.roleLabel,
            roomGameId: session?.gameId,
            roomShortCode: roomState.activeShareCode,
            isRoomHost: session?.isHost == true,
            hostOnline: roomState.hostOnline.value,
            virtualIp: myIp.isNotEmpty ? myIp : AppConstants.defaultVirtualIp,
            onCreateRoom: onCreateRoom,
            onJoinRoom: onJoinRoom,
            onShareRoom: onShareRoom,
            onDisconnect: onDisconnect,
          ),
          const SizedBox(height: AppDimensions.sectionGap),
          Expanded(
            child: RoomOpenGamesPanel(
              gameId: session?.gameId,
            ),
          ),
        ],
      );
    });
  }
}
