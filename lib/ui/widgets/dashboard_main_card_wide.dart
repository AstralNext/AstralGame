import 'package:flutter/material.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/ui/widgets/dashboard_main_card_base.dart';

/// 宽屏仪表盘右侧主卡片：已连接时仍显示网络配置；分享 / 断开为全宽主次按钮。
class DashboardMainCardWide extends DashboardMainCardBase {
  const DashboardMainCardWide({
    super.key,
    super.isConnected = false,
    super.username = '玩家',
    super.userAvatar,
    super.virtualIp = AppConstants.defaultVirtualIp,
    super.roomDisplayName,
    super.onSettingsTap,
    super.onCreateRoomTap,
    super.onJoinRoomTap,
    super.onShareRoomTap,
    super.onDisconnectTap,
    super.isCollapsed = false,
    super.showFirewall = true,
  });

  @override
  State<DashboardMainCardWide> createState() => _DashboardMainCardWideState();
}

class _DashboardMainCardWideState
    extends DashboardMainCardBaseState<DashboardMainCardWide> {
  @override
  bool get showNetworkWhenConnected => true;

  @override
  Widget buildConnectedActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.play_circle_outline, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              '操作',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            onPressed: widget.onShareRoomTap,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.brMedium,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.share_outlined, size: 18),
                SizedBox(width: 8),
                Text('分享房间'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            onPressed: widget.onDisconnectTap,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.brMedium,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.link_off_outlined, size: 18),
                SizedBox(width: 8),
                Text('断开连接'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
