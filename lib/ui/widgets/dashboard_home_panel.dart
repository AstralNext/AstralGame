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
    this.pausedRoomName,
    this.virtualIp,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onShareRoom,
    required this.onDisconnect,
    this.onResumeHost,
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
  final String? pausedRoomName;
  final String? virtualIp;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;
  final VoidCallback onShareRoom;
  final VoidCallback onDisconnect;
  final VoidCallback? onResumeHost;

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
              pausedRoomName: pausedRoomName,
              onCreate: onCreateRoom,
              onJoin: onJoinRoom,
              onResumeHost: onResumeHost,
            ),
    );
  }
}

class _IdleHome extends StatelessWidget {
  const _IdleHome({
    super.key,
    required this.username,
    this.pausedRoomName,
    required this.onCreate,
    required this.onJoin,
    this.onResumeHost,
  });

  final String username;
  final String? pausedRoomName;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback? onResumeHost;

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
            if (pausedRoomName != null &&
                pausedRoomName!.trim().isNotEmpty &&
                onResumeHost != null) ...[
              const SizedBox(height: 12),
              AstralCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '可重新开启',
                            style: textTheme.labelMedium?.copyWith(
                              color: palette.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pausedRoomName!,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '恢复后请把新短码发给好友',
                            style: textTheme.bodySmall?.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: onResumeHost,
                      child: const Text('重新开启'),
                    ),
                  ],
                ),
              ),
            ],
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
