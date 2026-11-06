import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/pages/dashboard_user_item.dart';
import 'package:astral_game/ui/widgets/dashboard_members_skeleton.dart';
import 'package:astral_game/ui/widgets/section_header.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 成员区标题：游戏名 · 成员 + 人数 + “简洁/详细”切换。
///
/// 宽屏与窄屏共用，避免两套标题/开关/保存逻辑改一处漏一处。
class RoomMembersHeader extends StatelessWidget {
  const RoomMembersHeader({
    super.key,
    required this.roomState,
    required this.nodeManagement,
  });

  final RoomState roomState;
  final NodeManagementService nodeManagement;

  @override
  Widget build(BuildContext context) {
    final settingsState = getIt<SettingsState>();
    final textTheme = Theme.of(context).textTheme;
    final palette = context.astralPalette;

    return Watch(
      (context) {
        final session = roomState.session.value;
        final game = session == null ? null : GameCatalog.byId(session.gameId);
        final title = [if (game != null) game.displayName, '成员'].join(' · ');
        final nodes = nodeManagement.userNodes.value;
        final compact = settingsState.memberListCompact.value;

        return SectionHeader(
          title: title,
          count: nodes.isEmpty ? null : nodes.length,
          tone: SectionHeaderTone.accent,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                compact ? '简洁' : '详细',
                style: textTheme.labelSmall?.copyWith(
                  color: palette.textTertiary,
                ),
              ),
              const SizedBox(width: AppDimensions.space4),
              Switch.adaptive(
                value: compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (value) {
                  settingsState.memberListCompact.value = value;
                  settingsState.saveToPersistence();
                },
              ),
            ],
          ),
        );
      },
      dependencies: [
        roomState.session,
        nodeManagement.userNodes,
        settingsState.memberListCompact,
      ],
    );
  }
}

/// 成员行。
///
/// [withDivider] 为 true 时用于窄屏分组列表（首行不画分割线、圆角按分组计算），
/// 宽屏传 false，与原先 `UserListWidget` 的独立圆角卡片一致。
class RoomMemberRow extends StatelessWidget {
  const RoomMemberRow({
    super.key,
    required this.node,
    required this.nodeManagement,
    required this.compact,
    this.index = 0,
    this.count = 1,
    this.withDivider = false,
  });

  final EnhancedNodeInfo node;
  final NodeManagementService nodeManagement;
  final bool compact;
  final int index;
  final int count;
  final bool withDivider;

  @override
  Widget build(BuildContext context) {
    final tile = DashboardUserItem(
      key: ValueKey<int>(node.peerId),
      node: node,
      nodeManagement: nodeManagement,
      grouped: withDivider,
      index: index,
      count: count,
      isLocal: nodeManagement.isLocalPeer(node.peerId),
      compact: compact,
    );
    if (!withDivider) return tile;
    return Column(
      children: [
        if (index > 0) const Divider(height: 1, indent: 72),
        tile,
      ],
    );
  }
}

/// 盒子布局的成员列表（宽屏右栏/卡片内使用）。
class RoomMembersPanel extends StatelessWidget {
  const RoomMembersPanel({
    super.key,
    required this.roomState,
    required this.nodeManagement,
  });

  final RoomState roomState;
  final NodeManagementService nodeManagement;

  @override
  Widget build(BuildContext context) {
    final settingsState = getIt<SettingsState>();

    return Watch(
      (context) {
        final nodes = nodeManagement.userNodes.value;
        final compact = settingsState.memberListCompact.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RoomMembersHeader(
              roomState: roomState,
              nodeManagement: nodeManagement,
            ),
            const SizedBox(height: AppDimensions.space12),
            Expanded(
              child: nodes.isEmpty
                  ? const DashboardMembersSkeleton()
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: nodes.length,
                      itemBuilder: (context, index) => RoomMemberRow(
                        node: nodes[index],
                        nodeManagement: nodeManagement,
                        compact: compact,
                      ),
                    ),
            ),
          ],
        );
      },
      dependencies: [
        nodeManagement.userNodes,
        nodeManagement.currentInstanceId,
        settingsState.memberListCompact,
      ],
    );
  }
}

/// Sliver 布局的成员列表（窄屏 `CustomScrollView` 内使用）。
class RoomMembersSliver extends StatelessWidget {
  const RoomMembersSliver({
    super.key,
    required this.roomState,
    required this.nodeManagement,
  });

  final RoomState roomState;
  final NodeManagementService nodeManagement;

  @override
  Widget build(BuildContext context) {
    final settingsState = getIt<SettingsState>();

    return Watch(
      (context) {
        final nodes = nodeManagement.userNodes.value;
        final compact = settingsState.memberListCompact.value;
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RoomMembersHeader(
                    roomState: roomState,
                    nodeManagement: nodeManagement,
                  ),
                  const SizedBox(height: AppDimensions.space8),
                  if (nodes.isEmpty) const DashboardMembersSkeleton(),
                ],
              ),
            ),
            if (nodes.isNotEmpty)
              SliverList.builder(
                itemCount: nodes.length,
                itemBuilder: (context, index) => RoomMemberRow(
                  node: nodes[index],
                  nodeManagement: nodeManagement,
                  compact: compact,
                  index: index,
                  count: nodes.length,
                  withDivider: true,
                ),
              ),
          ],
        );
      },
      dependencies: [
        nodeManagement.userNodes,
        nodeManagement.currentInstanceId,
        settingsState.memberListCompact,
      ],
    );
  }
}
