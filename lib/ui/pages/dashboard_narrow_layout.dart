import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/open_games_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/dashboard_home_panel.dart';
import 'package:astral_game/ui/widgets/room_members_section.dart';
import 'package:astral_game/ui/widgets/room_open_games_panel.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class DashboardNarrowLayout extends StatelessWidget {
  const DashboardNarrowLayout({
    super.key,
    required this.nodeManagement,
    required this.roomState,
    required this.callbacks,
    this.scrollController,
  });

  final NodeManagementService nodeManagement;
  final RoomState roomState;
  final DashboardCallbacks callbacks;

  /// Shell 注入的滚动控制器：重按当前 Tab 时用它回到顶部。
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final session = roomState.session.value;
      final showRoom = session != null;
      // 传输可用（TUN/VPN/SDR 就绪）才算已连接；实例存在与否不再是 UI 口径。
      final isConnected = roomState.isConnected.value;
      // 已有会话且仍在建联（含 Steam 启动期）。
      final isLinking = getIt<ConnectionService>().isLinking.value;

      final username = nodeManagement.currentUsername.value.trim();

      if (!showRoom) {
        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppDimensions.pagePaddingH,
                  AppDimensions.sectionGap,
                  AppDimensions.pagePaddingH,
                  AppDimensions.listBottomWithNav(context),
                ),
                child: DashboardHomePanel(
                  isConnected: false,
                  username: nodeManagement.currentUsername.value,
                  callbacks: callbacks,
                ),
              ),
            ),
          ],
        );
      }

      final active = session;
      return CustomScrollView(
        key: const PageStorageKey<String>('dashboard_narrow_scroll'),
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.pagePaddingH,
              AppDimensions.sectionGap,
              AppDimensions.pagePaddingH,
              AppDimensions.space8,
            ),
            sliver: SliverToBoxAdapter(
              child: _NarrowRoomHeader(
                roomState: roomState,
                isLinking: isLinking,
                username: username,
                gameId: active.gameId,
                callbacks: callbacks,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.pagePaddingH,
              AppDimensions.space8,
              AppDimensions.pagePaddingH,
              AppDimensions.space8,
            ),
            sliver: SliverToBoxAdapter(
              child: _NarrowOpenGamesSlot(
                gameId: active.gameId,
                isConnected: isConnected,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppDimensions.pagePaddingH,
              8,
              AppDimensions.pagePaddingH,
              AppDimensions.listBottomWithNav(context),
            ),
            sliver: RoomMembersSliver(
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
    required this.roomState,
    required this.isLinking,
    required this.username,
    required this.gameId,
    required this.callbacks,
  });

  final RoomState roomState;
  final bool isLinking;
  final String username;
  final String gameId;
  final DashboardCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      return DashboardHomePanel(
        isConnected: true,
        isLinking: isLinking,
        username: username,
        roomDisplayName: roomState.activeRoomDisplayLabel,
        roomGameId: gameId,
        roomShortCode: roomState.activeShareCode,
        callbacks: callbacks,
      );
    });
  }
}

class _NarrowOpenGamesSlot extends StatelessWidget {
  const _NarrowOpenGamesSlot({
    required this.gameId,
    required this.isConnected,
  });

  final String gameId;

  /// 开房面板只在传输可用后展示：建联途中没数据可看，提前展示只会闪一下空卡。
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final openGames = getIt<OpenGamesService>();
      final openListings = openGames.listings.value;
      final showOpenGames =
          isConnected && (openGames.isActive || openListings.isNotEmpty);
      if (!showOpenGames) return const SizedBox.shrink();
      final openGamesHeight = openListings.isEmpty ? 72.0 : 220.0;
      return AnimatedSize(
        duration: AppDimensions.motionSheet,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: openGamesHeight,
          width: double.infinity,
          child: RoomOpenGamesPanel(compact: true, gameId: gameId),
        ),
      );
    });
  }
}
