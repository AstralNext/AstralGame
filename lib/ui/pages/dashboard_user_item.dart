import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/ui/widgets/grouped_tile_shape.dart';
import 'package:flutter/material.dart';
import 'package:astral_game/utils/firewall_presentation.dart';
import 'package:astral_game/utils/network_presentation.dart';
import 'package:astral_game/utils/os_presentation.dart';
import 'package:astral_game/utils/platform_version_parser.dart';

class DashboardUserItem extends StatefulWidget {
  const DashboardUserItem({
    super.key,
    required this.node,
    this.grouped = false,
    this.index = 0,
    this.count = 1,
    this.compact = false,
    this.isRoomHost = false,
    this.onKick,
  });

  final EnhancedNodeInfo node;
  final bool grouped;
  final int index;
  final int count;
  final bool compact;
  /// 是否为当前房间房主。
  final bool isRoomHost;
  /// 房主踢人；非空时显示踢出按钮。
  final Future<void> Function(EnhancedNodeInfo node)? onKick;

  @override
  State<DashboardUserItem> createState() => _DashboardUserItemState();
}

class _DashboardUserItemState extends State<DashboardUserItem> {
  bool _isHovered = false;
  bool _kicking = false;

  Future<void> _confirmKick(BuildContext context) async {
    final onKick = widget.onKick;
    if (onKick == null) return;
    final name = widget.node.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('踢出成员'),
        content: Text('确定踢出「$name」？其进网凭据将被撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('踢出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _kicking = true);
    try {
      await onKick(widget.node);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已踢出 $name')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('踢出失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _kicking = false);
    }
  }

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
    final versionNumber = PlatformVersionParser.getVersionNumber(node.baseInfo.version);

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

    final row = Row(
          children: [
            _buildAvatar(colorScheme),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      node.customName != null
                          ? Text(
                              node.customName!,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface,
                              ),
                            )
                          : Text(
                              '...',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                            ),
                      if (widget.isRoomHost)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _MiniChip(
                            icon: Icons.star_rounded,
                            label: '房主',
                            background: colorScheme.primaryContainer,
                            foreground: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      if (platformName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _MiniChip(
                            icon: platformIcon,
                            label: platformName,
                            background: colorScheme.secondaryContainer,
                            foreground: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      if (network.hasLabel)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _MiniChip(
                            icon: network.icon,
                            label: network.shortLabel,
                            background: colorScheme.tertiaryContainer,
                            foreground: colorScheme.onTertiaryContainer,
                          ),
                        ),
                      if (firewall.hasLabel)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _MiniChip(
                            icon: firewall.icon,
                            label: firewall.shortLabel,
                            background: firewall.isEnabled == true
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest,
                            foreground: firewall.isEnabled == true
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: (network.hasLabel || firewall.hasLabel) ? 4 : 6,
                        ),
                        child: Text(
                          '${node.baseInfo.latencyMs.round()}ms',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: node.baseInfo.latencyMs < 100
                                ? AppColors.online
                                : node.baseInfo.latencyMs < 300
                                    ? AppColors.warning
                                    : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.online,
                                  borderRadius: AppRadius.brSmall,
                                ),
                                child: Text(
                                  '直连',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          if (versionNumber.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                versionNumber,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (peerEnvLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Tooltip(
                      message: _peerClientEnvFull(node),
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
                  if (node.baseInfo.lossRate > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '丢包: ${node.baseInfo.lossRate.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (widget.onKick != null && !widget.isRoomHost)
              IconButton(
                tooltip: '踢出',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: _kicking ? null : () => _confirmKick(context),
                icon: _kicking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.person_remove_outlined,
                        color: colorScheme.error,
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
        widget.grouped ? 12 : 12,
        widget.grouped ? 12 : 12,
        widget.grouped ? 12 : 12,
      ),
      child: row,
    );

    if (widget.grouped) {
      return Material(
        color: Colors.transparent,
        shape: groupedTileShape(index: widget.index, count: widget.count),
        clipBehavior: Clip.antiAlias,
        child: padded,
      );
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
        child: padded,
      ),
    );
  }

  /// 单行摘要（列表内展示）：仅「系统版本 · 应用版本」，例如 `10.0.26200 · 1.0.0+1`。
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
    final size = 36.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primaryContainer,
        border: Border.all(color: colorScheme.outline, width: 1),
      ),
      child: widget.node.avatar != null
          ? ClipOval(
              child: Image.memory(
                widget.node.avatar!,
                fit: BoxFit.cover,
                width: size,
                height: size,
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