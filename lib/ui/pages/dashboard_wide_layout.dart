import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/ui/pages/dashboard_history_item.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/dashboard_list_section.dart';
import 'package:astral_game/ui/widgets/dashboard_main_card_wide.dart';
import 'package:astral_game/ui/widgets/user_list_widget.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 仪表盘宽屏布局
class DashboardWideLayout extends StatelessWidget {
  const DashboardWideLayout({
    super.key,
    required this.nodeManagement,
    required this.connectionService,
    required this.screenStateService,
    required this.roomState,
    required this.onSettings,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
    required this.onJoinHistory,
  });

  final NodeManagementService nodeManagement;
  final ConnectionService connectionService;
  final ScreenStateService screenStateService;
  final RoomState roomState;
  final VoidCallback onSettings;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;
  final void Function(String) onJoinHistory;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 6, child: _buildLeftPanel(context)),
        const SizedBox(width: AppDimensions.sectionGap),
        Expanded(flex: 4, child: _buildRightPanel(context)),
      ],
    );
  }

  Widget _buildLeftPanel(BuildContext context) {
    return Watch((context) {
      final palette = context.astralPalette;
      final textTheme = Theme.of(context).textTheme;
      final instanceId = nodeManagement.currentInstanceId.value;
      final isRunning = instanceId != null;
      final isNarrow = screenStateService.isNarrow;
      final roomLabel = roomState.activeRoomDisplayLabel;
      final title = isRunning
          ? (roomLabel != null && roomLabel.isNotEmpty
              ? '$roomLabel · 在线用户'
              : '在线用户')
          : '加入历史';

      return AstralCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: textTheme.labelLarge?.copyWith(
                color: palette.accent,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            isNarrow
                ? (isRunning
                      ? UserListWidget(
                          users: nodeManagement.userNodes.value,
                          shrinkWrap: true,
                        )
                      : _buildJoinHistory(context, shrinkWrap: true))
                : Expanded(
                    child: isRunning
                        ? UserListWidget(
                            users: nodeManagement.userNodes.value,
                            physics: const AlwaysScrollableScrollPhysics(),
                          )
                        : _buildJoinHistoryScrollable(context),
                  ),
          ],
        ),
      );
    });
  }

  Widget _buildRightPanel(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: constraints.maxHeight,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Watch((context) {
                final isConnected = nodeManagement.isRunning;
                final myIp = nodeManagement.myVirtualIpv4.value;
                final virtualIp =
                    myIp.isNotEmpty ? myIp : AppConstants.defaultVirtualIp;
                final username = nodeManagement.currentUsername.value;
                final avatar = nodeManagement.currentUserAvatar.value;

                return DashboardMainCardWide(
                  isConnected: isConnected,
                  username: username,
                  userAvatar: avatar,
                  virtualIp: virtualIp,
                  roomDisplayName: roomState.activeRoomDisplayLabel,
                  onSettingsTap: onSettings,
                  onCreateRoomTap: onCreateRoom,
                  onJoinRoomTap: onJoinRoom,
                  onShareRoomTap: onShareRoom,
                  onDisconnectTap: onDisconnect,
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryList(List<RoomMod> history) {
    return Column(
      children: [
        for (var i = 0; i < history.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 56),
          DashboardHistoryItem(
            key: ValueKey<String>(history[i].shareCode),
            room: history[i],
            grouped: true,
            index: i,
            count: history.length,
            onJoin: () => onJoinHistory(history[i].shareCode),
          ),
        ],
      ],
    );
  }

  Widget _buildJoinHistory(BuildContext context, {required bool shrinkWrap}) {
    return Watch((context) {
      final history = roomState.rooms;

      if (history.isEmpty) {
        return const DashboardListEmptyHint(
          icon: Icons.history_outlined,
          message: '暂无记录',
          detail: '创建或加入房间后会出现在这里',
        );
      }

      return _buildHistoryList(history);
    });
  }

  Widget _buildJoinHistoryScrollable(BuildContext context) {
    return Watch((context) {
      final history = roomState.rooms;

      if (history.isEmpty) {
        return const DashboardListEmptyHint(
          icon: Icons.history_outlined,
          message: '暂无记录',
          detail: '创建或加入房间后会出现在这里',
        );
      }

      return ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: history.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 56),
        itemBuilder: (context, index) {
          final room = history[index];
          return DashboardHistoryItem(
            key: ValueKey<String>(room.shareCode),
            room: room,
            grouped: true,
            index: index,
            count: history.length,
            onJoin: () => onJoinHistory(room.shareCode),
          );
        },
      );
    });
  }
}
