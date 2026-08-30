import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/services/isp_info_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/grouped_tile_shape.dart';
import 'package:astral_game/utils/firewall_presentation.dart';
import 'package:astral_game/utils/network_presentation.dart';
import 'package:astral_game/utils/os_presentation.dart';
import 'package:astral_game/utils/platform_version_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

class DashboardUserItem extends StatefulWidget {
  const DashboardUserItem({
    super.key,
    required this.node,
    required this.nodeManagement,
    this.grouped = false,
    this.index = 0,
    this.count = 1,
    this.compact = false,
    this.isRoomHost = false,
  });

  final EnhancedNodeInfo node;
  final NodeManagementService nodeManagement;
  final bool grouped;
  final int index;
  final int count;
  final bool compact;
  /// 是否为当前房间房主。
  final bool isRoomHost;

  @override
  State<DashboardUserItem> createState() => _DashboardUserItemState();
}

class _DashboardUserItemState extends State<DashboardUserItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final hasIpv4 = node.hasValidIpv4;
    final hasIpv6 = node.hasValidIpv6;
    final ipDisplayText = hasIpv4 ? node.ipv4 : '未分配 IP';
    final isDirect = node.baseInfo.cost <= 1;
    final os = OsPresentation.forNode(node);
    final network = NetworkPresentation.fromWire(node.peerNetwork);
    final firewall = FirewallPresentation.fromWire(node.peerFirewall);
    final versionNumber =
        PlatformVersionParser.getVersionNumber(node.baseInfo.version);
    final peerEnvLine = _peerClientEnvLabel(node);

    return RepaintBoundary(
      child: _buildContent(
        context,
        node,
        os.shortLabel,
        os.icon,
        network,
        firewall,
        versionNumber,
        hasIpv4,
        hasIpv6,
        ipDisplayText,
        isDirect,
        peerEnvLine,
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    EnhancedNodeInfo node,
    String platformName,
    IconData platformIcon,
    NetworkPresentation network,
    FirewallPresentation firewall,
    String versionNumber,
    bool hasIpv4,
    bool hasIpv6,
    String ipDisplayText,
    bool isDirect,
    String peerEnvLine,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final palette = context.astralPalette;
    final borderRadius = widget.grouped
        ? groupedTileBorderRadius(index: widget.index, count: widget.count)
        : AppRadius.brMedium;

    return _UserTileShell(
      grouped: widget.grouped,
      index: widget.index,
      count: widget.count,
      borderRadius: borderRadius,
      isHovered: _isHovered,
      onHoverChanged: (v) => setState(() => _isHovered = v),
      onTap: () => _copyIp(context, hasIpv4: hasIpv4, ipv4: node.ipv4),
      colorScheme: colorScheme,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.grouped ? 16 : 12,
          12,
          12,
          12,
        ),
        child: _UserMainContentRow(
          node: node,
          colorScheme: colorScheme,
          accentColor: palette.accent,
          platformName: platformName,
          platformIcon: platformIcon,
          network: network,
          firewall: firewall,
          versionNumber: versionNumber,
          hasIpv4: hasIpv4,
          hasIpv6: hasIpv6,
          ipDisplayText: ipDisplayText,
          isDirect: isDirect,
          peerEnvLine: peerEnvLine,
          isRoomHost: widget.isRoomHost,
          nodeManagement: widget.nodeManagement,
          latencyColor: _latencyColor,
          peerClientEnvFull: () => _peerClientEnvFull(node),
          avatarWidget: _UserAvatar(
            avatar: widget.node.avatar,
            colorScheme: colorScheme,
          ),
        ),
      ),
    );
  }

  Color _latencyColor(double latencyMs) {
    if (latencyMs < 100) return AppColors.online;
    if (latencyMs < 300) return AppColors.warning;
    return AppColors.error;
  }

  Future<void> _copyIp(
    BuildContext context, {
    required bool hasIpv4,
    required String ipv4,
  }) async {
    if (!hasIpv4) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该成员尚未分配 IP')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: ipv4));
    HapticFeedback.selectionClick();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 IP：$ipv4')),
    );
  }

  /// 单行摘要（列表内展示）：仅「系统版本 · 应用版本」，例如 `10.0.26200 · 1.0.41`。
  String _peerClientEnvLabel(EnhancedNodeInfo node) {
    final parts = <String>[];
    final osVer = node.peerOsVersion;
    if (osVer != null && osVer.isNotEmpty) {
      parts.add(osVer);
    }
    final ver = node.peerAppVersion;
    if (ver != null && ver.isNotEmpty) {
      parts.add(ver);
    }
    return parts.join(' · ');
  }

  /// Tooltip 完整文案。
  String _peerClientEnvFull(EnhancedNodeInfo node) {
    final lines = <String>[];
    final os = node.peerOs;
    final osVer = node.peerOsVersion;
    if (os != null && os.isNotEmpty) {
      lines.add('系统: ${_friendlyClientOs(os)}');
    }
    if (osVer != null && osVer.isNotEmpty) {
      lines.add('系统版本: $osVer');
    }
    final app = node.peerAppName;
    final ver = node.peerAppVersion;
    if (app != null && app.isNotEmpty) {
      lines.add('应用: $app');
    }
    if (ver != null && ver.isNotEmpty) {
      lines.add('应用版本: $ver');
    }
    final net = NetworkPresentation.fromWire(node.peerNetwork);
    if (net.hasLabel) {
      lines.add('网络: ${net.shortLabel}');
    }
    final fw = FirewallPresentation.fromWire(node.peerFirewall);
    if (fw.hasLabel) {
      lines.add('防火墙: ${fw.shortLabel}');
    }
    return lines.join('\n');
  }

  String _friendlyClientOs(String raw) {
    switch (raw.toLowerCase()) {
      case 'windows':
        return 'Windows';
      case 'macos':
        return 'macOS';
      case 'linux':
        return 'Linux';
      case 'android':
        return 'Android';
      case 'ios':
        return 'iOS';
      case 'web':
        return 'Web';
      default:
        return raw;
    }
  }

}

// ─── 拆分后的子 Widget ───────────────────────────────────────────────────────

/// 用户头像组件：圆形头像容器 + 图片或默认图标。
class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.avatar, required this.colorScheme});

  final Uint8List? avatar;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primaryContainer,
        border: Border.all(color: colorScheme.outline),
      ),
      child: avatar != null
          ? ClipOval(
              child: Image.memory(
                avatar!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                cacheWidth: (size * 2).round(),
                cacheHeight: (size * 2).round(),
                gaplessPlayback: true,
              ),
            )
          : Icon(
              Icons.person,
              size: size * 0.5,
              color: colorScheme.onPrimaryContainer,
            ),
    );
  }
}

/// 状态标签 chips 区域（运营商 / 平台 / 网络 / 防火墙 / 延迟）。
class _UserStatusChips extends StatelessWidget {
  const _UserStatusChips({
    required this.node,
    required this.platformName,
    required this.platformIcon,
    required this.network,
    required this.firewall,
    required this.colorScheme,
    required this.nodeManagement,
    required this.peerId,
    required this.latencyColor,
  });

  final EnhancedNodeInfo node;
  final String platformName;
  final IconData platformIcon;
  final NetworkPresentation network;
  final FirewallPresentation firewall;
  final ColorScheme colorScheme;
  final NodeManagementService nodeManagement;
  final int peerId;
  final Color Function(double) latencyColor;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      // 每个人都显示自己的运营商归属（本机走 Watch 实时刷新；远程 peer 由 peer RPC 更新 metadata）
      if (node.peerIsp case final isp?)
        _MiniChip(
          icon: Icons.router_rounded,
          label: isp,
          background: colorScheme.primaryContainer,
          foreground: colorScheme.onPrimaryContainer,
        ),
      if (platformName.isNotEmpty)
        _MiniChip(
          icon: platformIcon,
          label: platformName,
          background: colorScheme.secondaryContainer,
          foreground: colorScheme.onSecondaryContainer,
        ),
      if (network.hasLabel)
        _MiniChip(
          icon: network.icon,
          label: network.shortLabel,
          background: colorScheme.tertiaryContainer,
          foreground: colorScheme.onTertiaryContainer,
        ),
      if (firewall.hasLabel)
        _MiniChip(
          icon: firewall.icon,
          label: firewall.shortLabel,
          background: firewall.isEnabled == true
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          foreground: firewall.isEnabled == true
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      Watch((context) {
        final metrics = nodeManagement.linkMetricsOf(peerId).value;
        return Text(
          '${metrics.latencyMs.round()}ms',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: latencyColor(metrics.latencyMs),
          ),
        );
      }),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }
}

/// IP 信息 + 版本号 + 直连标签 + IPv6 + 环境信息 + 丢包率 行。
class _UserIpAndMetaRow extends StatelessWidget {
  const _UserIpAndMetaRow({
    required this.node,
    required this.colorScheme,
    required this.versionNumber,
    required this.hasIpv4,
    required this.hasIpv6,
    required this.ipDisplayText,
    required this.isDirect,
    required this.peerEnvLine,
    required this.nodeManagement,
    required this.peerClientEnvFull,
  });

  final EnhancedNodeInfo node;
  final ColorScheme colorScheme;
  final String versionNumber;
  final bool hasIpv4;
  final bool hasIpv6;
  final String ipDisplayText;
  final bool isDirect;
  final String peerEnvLine;
  final NodeManagementService nodeManagement;
  final String Function() peerClientEnvFull;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              ipDisplayText,
              style: TextStyle(
                fontSize: 12,
                color: hasIpv4
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            if (isDirect)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.online,
                  borderRadius: AppRadius.brSmall,
                ),
                child: const Text(
                  '直连',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            if (versionNumber.isNotEmpty)
              Text(
                versionNumber,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
        if (hasIpv6)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              node.ipv6,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
              ),
            ),
          ),
        if (peerEnvLine.isNotEmpty) ...[
          const SizedBox(height: 4),
          Tooltip(
            message: peerClientEnvFull(),
            child: Text(
              peerEnvLine,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        Watch((context) {
          final metrics = nodeManagement.linkMetricsOf(node.peerId).value;
          if (metrics.lossRate <= 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '丢包: ${metrics.lossRate.toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.error,
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// 主内容行（头像 + 信息列 + 状态指示点）。
class _UserMainContentRow extends StatelessWidget {
  const _UserMainContentRow({
    required this.node,
    required this.colorScheme,
    required this.accentColor,
    required this.platformName,
    required this.platformIcon,
    required this.network,
    required this.firewall,
    required this.versionNumber,
    required this.hasIpv4,
    required this.hasIpv6,
    required this.ipDisplayText,
    required this.isDirect,
    required this.peerEnvLine,
    required this.isRoomHost,
    required this.nodeManagement,
    required this.latencyColor,
    required this.peerClientEnvFull,
    required this.avatarWidget,
  });

  final EnhancedNodeInfo node;
  final ColorScheme colorScheme;
  final Color accentColor;
  final String platformName;
  final IconData platformIcon;
  final NetworkPresentation network;
  final FirewallPresentation firewall;
  final String versionNumber;
  final bool hasIpv4;
  final bool hasIpv6;
  final String ipDisplayText;
  final bool isDirect;
  final String peerEnvLine;
  final bool isRoomHost;
  final NodeManagementService nodeManagement;
  final Color Function(double) latencyColor;
  final String Function() peerClientEnvFull;
  final Widget avatarWidget;

  int get peerId => node.peerId;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        avatarWidget,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.customName ?? '...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: node.customName != null
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 4),
              _UserStatusChips(
                node: node,
                platformName: platformName,
                platformIcon: platformIcon,
                network: network,
                firewall: firewall,
                colorScheme: colorScheme,
                nodeManagement: nodeManagement,
                peerId: node.peerId,
                latencyColor: latencyColor,
              ),
              const SizedBox(height: 4),
              _UserIpAndMetaRow(
                node: node,
                colorScheme: colorScheme,
                versionNumber: versionNumber,
                hasIpv4: hasIpv4,
                hasIpv6: hasIpv6,
                ipDisplayText: ipDisplayText,
                isDirect: isDirect,
                peerEnvLine: peerEnvLine,
                nodeManagement: nodeManagement,
                peerClientEnvFull: peerClientEnvFull,
              ),
            ],
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

/// 外层交互容器（Padding / Material / InkWell / 分组样式 / MouseRegion）。
class _UserTileShell extends StatelessWidget {
  const _UserTileShell({
    required this.grouped,
    required this.index,
    required this.count,
    required this.borderRadius,
    required this.isHovered,
    required this.onHoverChanged,
    required this.onTap,
    required this.colorScheme,
    required this.child,
  });

  final bool grouped;
  final int index;
  final int count;
  final BorderRadius borderRadius;
  final bool isHovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = grouped
        ? groupedTileShape(index: index, count: count)
        : RoundedRectangleBorder(borderRadius: borderRadius);

    final ink = Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: grouped ? null : borderRadius,
        customBorder: grouped ? shape : null,
        child: child,
      ),
    );

    if (grouped) return ink;

    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isHovered
              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: ink,
      ),
    );
  }
}

// ─── 原有子 Widget ──────────────────────────────────────────────────────────

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.brSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
