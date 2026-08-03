import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/ui/pages/dashboard_history_item.dart';
import 'package:astral_game/ui/pages/dashboard_user_item.dart';
import 'package:astral_game/ui/widgets/dashboard_list_section.dart';
import 'package:astral_game/ui/widgets/dashboard_main_card_narrow.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 仪表盘窄屏：主卡片 + 下方列表分区（无吸顶标题、无额外色块底）。
class DashboardNarrowLayout extends StatelessWidget {
  const DashboardNarrowLayout({
    super.key,
    required this.nodeManagement,
    required this.connectionService,
    required this.roomState,
    required this.onSettings,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
    required this.onRemoveRoom,
    required this.onJoinHistory,
  });

  final NodeManagementService nodeManagement;
  final ConnectionService connectionService;
  final RoomState roomState;
  final VoidCallback onSettings;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;
  final void Function(RoomMod) onRemoveRoom;
  final void Function(String) onJoinHistory;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final isConnected = nodeManagement.isRunning;
      final nodes = nodeManagement.userNodes.value;
      final history = roomState.rooms;
      final roomLabel = roomState.activeRoomDisplayLabel;

      return CustomScrollView(
        key: const PageStorageKey<String>('dashboard_narrow_scroll'),
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.pagePaddingH,
              AppDimensions.pagePaddingV,
              AppDimensions.pagePaddingH,
              12,
            ),
            sliver: SliverToBoxAdapter(
              child: _MainCardBlock(
                nodeManagement: nodeManagement,
                roomState: roomState,
                onSettings: onSettings,
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
              4,
              AppDimensions.pagePaddingH,
              24,
            ),
            sliver: SliverToBoxAdapter(
              child: isConnected
                  ? _buildUsersSection(nodes, roomLabel)
                  : _buildHistorySection(history),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildUsersSection(List<EnhancedNodeInfo> nodes, String? roomLabel) {
    final sectionTitle = roomLabel != null && roomLabel.isNotEmpty
        ? '$roomLabel · 在线用户'
        : '在线用户';
    if (nodes.isEmpty) {
      return DashboardListSection(
        title: sectionTitle,
        useCard: false,
        child: DashboardListEmptyHint(
          icon: Icons.people_outline,
          message: '暂无在线用户',
        ),
      );
    }

    return DashboardListSection(
      title: sectionTitle,
      count: nodes.length,
      child: Column(
        children: [
          for (var i = 0; i < nodes.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            DashboardUserItem(
              key: ValueKey<int>(nodes[i].peerId),
              node: nodes[i],
              grouped: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<RoomMod> history) {
    if (history.isEmpty) {
      return const DashboardListSection(
        title: '加入历史',
        subtitle: '创建或加入房间后会出现在这里',
        useCard: false,
        child: DashboardListEmptyHint(
          icon: Icons.history_outlined,
          message: '暂无记录',
        ),
      );
    }

    return DashboardListSection(
      title: '加入历史',
      count: history.length,
      child: Column(
        children: [
          for (var i = 0; i < history.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            DashboardDismissibleHistoryItem(
              key: ValueKey<String>(history[i].shareCode),
              room: history[i],
              grouped: true,
              index: i,
              count: history.length,
              onJoin: () => onJoinHistory(history[i].shareCode),
              onRemove: onRemoveRoom,
            ),
          ],
        ],
      ),
    );
  }
}

class _MainCardBlock extends StatelessWidget {
  const _MainCardBlock({
    required this.nodeManagement,
    required this.roomState,
    required this.onSettings,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
  });

  final NodeManagementService nodeManagement;
  final RoomState roomState;
  final VoidCallback onSettings;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final isConnected = nodeManagement.isRunning;
      final myIp = nodeManagement.myVirtualIpv4.value;
      final virtualIp =
          myIp.isNotEmpty ? myIp : AppConstants.defaultVirtualIp;
      final username = nodeManagement.currentUsername.value;
      final avatar = nodeManagement.currentUserAvatar.value;

      return DashboardMainCardNarrow(
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
    });
  }
}
