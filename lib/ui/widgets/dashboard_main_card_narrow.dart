import 'package:flutter/material.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/ui/widgets/dashboard_main_card_base.dart';

/// 窄屏仪表盘顶部主卡片：已连接时隐藏网络配置；分享 / 断开为一行紧凑按钮。
class DashboardMainCardNarrow extends DashboardMainCardBase {
  const DashboardMainCardNarrow({
    super.key,
    super.isConnected = false,
    super.username = '玩家',
    super.userAvatar,
    super.virtualIp = AppConstants.defaultVirtualIp,
    super.roomDisplayName,
    super.roomRoleLabel,
    super.roomGameId,
    super.roomShortCode,
    super.isRoomHost = false,
    super.onSettingsTap,
    super.onCreateRoomTap,
    super.onJoinRoomTap,
    super.onShareRoomTap,
    super.onDisconnectTap,
    super.isCollapsed = false,
    super.showFirewall = true,
  });

  @override
  State<DashboardMainCardNarrow> createState() =>
      _DashboardMainCardNarrowState();
}

class _DashboardMainCardNarrowState
    extends DashboardMainCardBaseState<DashboardMainCardNarrow> {
  @override
  bool get showNetworkWhenConnected => false;

  @override
  Widget buildConnectedActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          if (widget.isRoomHost) ...[
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: widget.onShareRoomTap,
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('分享房间'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          TextButton.icon(
            onPressed: widget.onDisconnectTap,
            icon: const Icon(Icons.link_off_outlined, size: 18),
            label: const Text('断开'),
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.error,
              minimumSize: const Size(64, 40),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }
}
