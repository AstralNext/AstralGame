import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/services/node_management_service.dart';
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

    final chips = <Widget>[
      if (widget.isRoomHost)
        _MiniChip(
          icon: Icons.star_rounded,
          label: '房主',
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
          final metrics = widget.nodeManagement
              .linkMetricsOf(node.peerId)
              .value;
          return Text(
            '${metrics.latencyMs.round()}ms',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _latencyColor(metrics.latencyMs),
            ),
          );
        }),
    ];

    final row = Row(
      children: [
        _buildAvatar(colorScheme),
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
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: chips,
                ),
              ],
              const SizedBox(height: 4),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
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
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
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
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.9,
                      ),
                    ),
                  ),
                ),
              if (peerEnvLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Tooltip(
                  message: _peerClientEnvFull(node),
                  child: Text(
                    peerEnvLine,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.75,
                      ),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              Watch((context) {
                final metrics = widget.nodeManagement
                    .linkMetricsOf(node.peerId)
                    .value;
                if (metrics.lossRate <= 0) {
                  return const SizedBox.shrink();
                }
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
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );

    final padded = Padding(
      padding: EdgeInsets.fromLTRB(
        widget.grouped ? 16 : 12,
        12,
        12,
        12,
      ),
      child: row,
    );

    final ink = Material(
      color: Colors.transparent,
      shape: widget.grouped
          ? groupedTileShape(index: widget.index, count: widget.count)
          : RoundedRectangleBorder(borderRadius: borderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _copyIp(context, hasIpv4: hasIpv4, ipv4: node.ipv4),
        borderRadius: widget.grouped ? null : borderRadius,
        customBorder: widget.grouped
            ? groupedTileShape(index: widget.index, count: widget.count)
            : null,
        child: padded,
      ),
    );

    if (widget.grouped) {
      return ink;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: _isHovered
              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: ink,
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

  Widget _buildAvatar(ColorScheme colorScheme) {
    const size = 36.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primaryContainer,
        border: Border.all(color: colorScheme.outline),
      ),
      child: widget.node.avatar != null
          ? ClipOval(
              child: Image.memory(
                widget.node.avatar!,
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
