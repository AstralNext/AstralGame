import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/dashboard_connected_room_card.dart';
import 'package:astral_game/ui/widgets/dashboard_create_join_pill.dart';
import 'package:astral_game/ui/widgets/dashboard_scenery_card.dart';
import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:flutter/material.dart';

/// 联机页：空闲为风景欢迎卡 + 底部信息 + FAB；已连接为房间卡。
class DashboardHomePanel extends StatelessWidget {
  const DashboardHomePanel({
    super.key,
    required this.isConnected,
    this.isLinking = false,
    this.username,
    this.roomDisplayName,
    this.roomRoleLabel,
    this.roomGameId,
    this.roomShortCode,
    this.isRoomHost = false,
    this.hostOnline = true,
    this.virtualIp,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
  });

  final bool isConnected;

  /// 已有短码/会话，组网仍在进行中。
  final bool isLinking;
  final String? username;
  final String? roomDisplayName;
  final String? roomRoleLabel;
  final String? roomGameId;
  final String? roomShortCode;
  final bool isRoomHost;
  final bool hostOnline;
  final String? virtualIp;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: isConnected
          ? ConnectedRoomCard(
              key: const ValueKey('connected'),
              roomDisplayName: roomDisplayName ?? '房间',
              roomRoleLabel: roomRoleLabel,
              roomGameId: roomGameId,
              roomShortCode: roomShortCode,
              isRoomHost: isRoomHost,
              hostOnline: hostOnline,
              isLinking: isLinking,
              virtualIp: virtualIp,
              onShare: onShareRoom,
              onDisconnect: onDisconnect,
            )
          : _IdleHome(
              key: const ValueKey('idle'),
              username: username?.trim().isNotEmpty == true
                  ? username!.trim()
                  : 'Player',
              onCreate: onCreateRoom,
              onJoin: onJoinRoom,
            ),
    );
  }
}

class _IdleHome extends StatelessWidget {
  const _IdleHome({
    super.key,
    required this.username,
    required this.onCreate,
    required this.onJoin,
  });

  final String username;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final version = ClientRuntimeInfo.appVersion;
    final os = ClientRuntimeInfo.operatingSystemVersion;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DailySceneryCard(username: username),
            ),
            const SizedBox(height: 16),
            Text(
              'v$version',
              style: textTheme.labelMedium?.copyWith(
                color: palette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              os,
              style: textTheme.labelSmall?.copyWith(
                color: palette.textTertiary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // 给右下角胶囊按钮留空
            const SizedBox(height: 64),
          ],
        ),
        Positioned(
          right: 0,
          bottom: 4,
          child: CreateJoinPill(
            onCreate: onCreate,
            onJoin: onJoin,
          ),
        ),
      ],
    );
  }
}
