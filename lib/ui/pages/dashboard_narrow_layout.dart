import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/open_games_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/pages/dashboard_user_item.dart';
import 'package:astral_game/ui/widgets/dashboard_home_panel.dart';
import 'package:astral_game/ui/widgets/dashboard_list_section.dart';
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
    this.onResumeHost,
  });

  final NodeManagementService nodeManagement;
  final RoomState roomState;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;
  final VoidCallback? onResumeHost;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final isConnected = nodeManagement.isRunning;
      final nodes = nodeManagement.userNodes.value;
      final myIp = nodeManagement.myVirtualIpv4.value;
      final session = roomState.session.value;
      final paused = roomState.pausedHost.value;
      final hostOnline = roomState.hostOnline.value;
      final openGames = getIt<OpenGamesService>();
      final openListings = openGames.listings.value;
      final openActive = openGames.isActive;

      if (!isConnected) {
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
            pausedRoomName: paused?.displayName,
            onCreateRoom: onCreateRoom,
            onJoinRoom: onJoinRoom,
            onShareRoom: onShareRoom,
            onDisconnect: onDisconnect,
            onResumeHost: onResumeHost,
          ),
        );
      }

      final showOpenGames = openActive || openListings.isNotEmpty;
      final openGamesHeight = openListings.isEmpty ? 72.0 : 220.0;

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
              child: DashboardHomePanel(
                isConnected: true,
                username: nodeManagement.currentUsername.value,
                roomDisplayName: roomState.activeRoomDisplayLabel,
                roomRoleLabel: session?.roleLabel,
                roomGameId: session?.gameId,
                roomShortCode: roomState.activeShareCode,
                isRoomHost: session?.isHost == true,
                hostOnline: hostOnline,
                virtualIp:
                    myIp.isNotEmpty ? myIp : AppConstants.defaultVirtualIp,
                onCreateRoom: onCreateRoom,
                onJoinRoom: onJoinRoom,
                onShareRoom: onShareRoom,
                onDisconnect: onDisconnect,
              ),
            ),
          ),
          if (showOpenGames)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.pagePaddingH,
                8,
                AppDimensions.pagePaddingH,
                8,
              ),
              sliver: SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: openGamesHeight,
                    width: double.infinity,
                    child: RoomOpenGamesPanel(
                      compact: true,
                      gameId: session?.gameId,
                    ),
                  ),
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
            sliver: SliverToBoxAdapter(
              child: _MembersBlock(
                nodes: nodes,
                roomState: roomState,
                nodeManagement: nodeManagement,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _MembersBlock extends StatelessWidget {
  const _MembersBlock({
    required this.nodes,
    required this.roomState,
    required this.nodeManagement,
  });

  final List<EnhancedNodeInfo> nodes;
  final RoomState roomState;
  final NodeManagementService nodeManagement;

  @override
  Widget build(BuildContext context) {
    final session = roomState.session.value;
    final game = session == null ? null : GameCatalog.byId(session.gameId);
    final title = [
      if (game != null) game.name,
      '成员',
    ].join(' · ');

    if (nodes.isEmpty) {
      return DashboardListSection(
        title: title,
        useCard: false,
        child: const DashboardMembersSkeleton(),
      );
    }

    return DashboardListSection(
      title: title,
      count: nodes.length,
      child: Column(
        children: [
          for (var i = 0; i < nodes.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            DashboardUserItem(
              key: ValueKey<int>(nodes[i].peerId),
              node: nodes[i],
              grouped: true,
              index: i,
              count: nodes.length,
              isRoomHost: session != null &&
                  nodeManagement.isRoomHostPeer(
                    nodes[i].peerId,
                    sessionIsHost: session.isHost,
                    isCredentialPeer: nodes[i].isCredentialPeer,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
