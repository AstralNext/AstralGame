import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/dashboard_home_panel.dart';
import 'package:astral_game/ui/widgets/room_members_section.dart';
import 'package:astral_game/ui/widgets/room_open_games_panel.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class DashboardWideLayout extends StatelessWidget {
  const DashboardWideLayout({
    super.key,
    required this.nodeManagement,
    required this.roomState,
    required this.callbacks,
  });

  final NodeManagementService nodeManagement;
  final RoomState roomState;
  final DashboardCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final session = roomState.session.value;
      final showRoom = session != null;

      final Widget content;
      if (!showRoom) {
        content = Padding(
          // 左侧不再额外留白：主体直接贴到页面内边距，靠近侧栏胶囊。
          padding: const EdgeInsets.fromLTRB(0, 0, AppDimensions.space4, 0),
          child: DashboardHomePanel(
            isConnected: false,
            username: nodeManagement.currentUsername.value,
            callbacks: callbacks,
          ),
        );
      } else {
        content = Row(
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
                callbacks: callbacks,
              ),
            ),
          ],
        );
      }

      return content;
    });
  }
}

class _MembersPane extends StatelessWidget {
  const _MembersPane({required this.nodeManagement, required this.roomState});

  final NodeManagementService nodeManagement;
  final RoomState roomState;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: palette.divider.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimensions.space16,
          AppDimensions.space16,
          AppDimensions.space16,
          AppDimensions.space12,
        ),
        child: RoomMembersPanel(
          roomState: roomState,
          nodeManagement: nodeManagement,
        ),
      ),
    );
  }
}

class _RoomPane extends StatelessWidget {
  const _RoomPane({
    required this.nodeManagement,
    required this.roomState,
    required this.callbacks,
  });

  final NodeManagementService nodeManagement;
  final RoomState roomState;
  final DashboardCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      // 传输可用（TUN/VPN/SDR 就绪）才算已连接；实例存在与否不再是 UI 口径。
      final isConnected = roomState.isConnected.value;
      // 已有会话且仍在建联（含 Steam 启动期）。
      final isLinking = getIt<ConnectionService>().isLinking.value;
      final session = roomState.session.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardHomePanel(
            isConnected: true,
            isLinking: isLinking,
            roomDisplayName: roomState.activeRoomDisplayLabel,
            roomGameId: session?.gameId,
            roomShortCode: roomState.activeShareCode,
            hostOnline: roomState.hostOnline.value,
            callbacks: callbacks,
          ),
          const SizedBox(height: AppDimensions.sectionGap),
          Expanded(
            child: isConnected
                ? RoomOpenGamesPanel(gameId: session?.gameId)
                : const SizedBox.shrink(),
          ),
        ],
      );
    });
  }
}
