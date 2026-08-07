import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/services/firewall_service.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:astral_game/utils/runtime_platform.dart';

/// 仪表盘主卡片公共字段与布局骨架；宽/窄屏子类只覆写 [showNetworkWhenConnected] 与 [buildConnectedActions]。
abstract class DashboardMainCardBase extends StatefulWidget {
  const DashboardMainCardBase({
    super.key,
    this.isConnected = false,
    this.username = '玩家',
    this.userAvatar,
    this.virtualIp = AppConstants.defaultVirtualIp,
    this.roomDisplayName,
    this.roomRoleLabel,
    this.roomGameId,
    this.roomShortCode,
    this.isRoomHost = false,
    this.onSettingsTap,
    this.onCreateRoomTap,
    this.onJoinRoomTap,
    this.onShareRoomTap,
    this.onDisconnectTap,
    this.isCollapsed = false,
    this.showFirewall = true,
  });

  final bool isConnected;
  final String username;
  final Uint8List? userAvatar;
  final String virtualIp;
  /// 已连接时展示的房间名；未连接可为 null。
  final String? roomDisplayName;
  /// 「房主」或「成员」。
  final String? roomRoleLabel;
  final String? roomGameId;
  final String? roomShortCode;
  final bool isRoomHost;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onCreateRoomTap;
  final VoidCallback? onJoinRoomTap;
  final VoidCallback? onShareRoomTap;
  final VoidCallback? onDisconnectTap;
  final bool isCollapsed;
  final bool showFirewall;

  @override
  State<DashboardMainCardBase> createState();
}

abstract class DashboardMainCardBaseState<W extends DashboardMainCardBase>
    extends State<W> {
  bool _firewallEnabled = false;
  bool _isLoadingFirewall = true;

  /// 已连接时是否仍显示「网络配置」区块（宽屏 true，窄屏 false）。
  bool get showNetworkWhenConnected;

  @override
  void initState() {
    super.initState();
    _loadFirewallStatus();
  }

  Future<void> _loadFirewallStatus() async {
    if (!kIsWeb && RuntimePlatform.operatingSystem == 'windows') {
      try {
        final firewallService = getIt<FirewallService>();
        await firewallService.refreshPrivateProfile();
        final status = firewallService.privateProfileEnabled.value ?? false;
        if (mounted) {
          setState(() {
            _firewallEnabled = status;
            _isLoadingFirewall = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isLoadingFirewall = false);
        }
      }
    } else {
      if (mounted) {
        setState(() => _isLoadingFirewall = false);
      }
    }
  }

  Future<void> _toggleFirewall(bool enable) async {
    setState(() => _firewallEnabled = enable);
    try {
      final firewallService = getIt<FirewallService>();
      await firewallService.setPrivateFirewallStatus(enable);
    } catch (_) {
      if (mounted) {
        setState(() => _firewallEnabled = !enable);
      }
    }
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userAvatar != widget.userAvatar) {
      setState(() {});
    }
  }

  Widget buildUserSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        AvatarWidget(
          avatar: widget.userAvatar,
          size: 48,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.username,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.isConnected &&
                  widget.roomDisplayName != null &&
                  widget.roomDisplayName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (GameCatalog.byId(widget.roomGameId) != null) ...[
                      GameLogo(
                        game: GameCatalog.byId(widget.roomGameId)!,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                    ] else ...[
                      Icon(
                        Icons.meeting_room_outlined,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        widget.roomDisplayName!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (widget.roomRoleLabel != null &&
                        widget.roomRoleLabel!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.roomRoleLabel!,
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (widget.roomShortCode != null &&
                    widget.roomShortCode!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '短码 ${widget.roomShortCode}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.lan_outlined,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      widget.virtualIp,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.edit_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
          onPressed: widget.onSettingsTap,
        ),
      ],
    );
  }

  Widget buildNetworkSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settingsState = getIt<SettingsState>();

    return Watch((context) {
      final palette = context.astralPalette;
      final disableP2p = settingsState.disableP2p.value;
      final udpBroadcastRelay = settingsState.enableUdpBroadcastRelay.value;
      final isWindows = RuntimePlatform.operatingSystem == 'windows';

      return Column(
        children: [
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.tune, color: colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '网络配置',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: context.astralPalette.canvas,
              borderRadius: AppRadius.brMedium,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: disableP2p
                        ? palette.accentMutedStrong
                        : palette.canvas,
                    borderRadius: AppRadius.brSmall,
                  ),
                  child: Icon(
                    Icons.route,
                    size: 18,
                    color: disableP2p
                        ? palette.accent
                        : palette.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '强制中转',
                        style: textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '禁用P2P直连',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: disableP2p,
                  onChanged: (value) {
                    settingsState.disableP2p.value = value;
                    settingsState.saveToPersistence();
                  },
                ),
              ],
            ),
          ),
          if (isWindows) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: AppRadius.brMedium,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: udpBroadcastRelay
                          ? palette.accentMutedStrong
                          : palette.canvas,
                      borderRadius: AppRadius.brSmall,
                    ),
                    child: Icon(
                      Icons.podcasts_outlined,
                      size: 18,
                      color: udpBroadcastRelay
                          ? palette.accent
                          : palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '强制 UDP 广播转发',
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '覆盖 JSON 规则；重连生效',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: udpBroadcastRelay,
                    onChanged: (value) {
                      settingsState.enableUdpBroadcastRelay.value = value;
                      settingsState.saveToPersistence();
                    },
                  ),
                ],
              ),
            ),
          ],
          if (widget.showFirewall && !kIsWeb && isWindows) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: AppRadius.brMedium,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _firewallEnabled
                          ? palette.accentMutedStrong
                          : palette.canvas,
                      borderRadius: AppRadius.brSmall,
                    ),
                    child: Icon(
                      Icons.shield,
                      size: 18,
                      color: _firewallEnabled
                          ? palette.accent
                          : palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '防火墙',
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          _isLoadingFirewall
                              ? '加载中...'
                              : (_firewallEnabled ? '已启用' : '已禁用'),
                          style: textTheme.bodySmall?.copyWith(
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isLoadingFirewall)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Switch(
                      value: _firewallEnabled,
                      onChanged: _toggleFirewall,
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    });
  }

  Widget buildDisconnectedActions(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const SizedBox(height: 6),
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
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            onPressed: widget.onCreateRoomTap,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.brMedium,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_box_outlined, size: 18),
                SizedBox(width: 8),
                Text('创建房间'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            onPressed: widget.onJoinRoomTap,
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.brMedium,
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.login_outlined, size: 18),
                SizedBox(width: 8),
                Text('加入房间'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildConnectedActions(BuildContext context);

  @override
  Widget build(BuildContext context) {
    final showNetwork =
        !widget.isConnected || showNetworkWhenConnected;

    return AstralCard(
      padding: const EdgeInsets.all(16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildUserSection(context),
            ClipRect(
              child: AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  children: [
                    if (showNetwork) buildNetworkSection(context),
                    widget.isConnected
                        ? buildConnectedActions(context)
                        : buildDisconnectedActions(context),
                  ],
                ),
                crossFadeState: widget.isCollapsed
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 300),
                firstCurve: Curves.easeInOut,
                secondCurve: Curves.easeInOut,
              ),
            ),
          ],
        ),
    );
  }
}
