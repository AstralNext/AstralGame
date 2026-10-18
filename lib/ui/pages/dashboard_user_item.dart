import 'package:astral_game/config/constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/ui/widgets/app_toast.dart';
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
    this.isLocal = false,
  });

  final EnhancedNodeInfo node;
  final NodeManagementService nodeManagement;
  final bool grouped;
  final int index;
  final int count;
  final bool compact;

  /// 是否为本机节点。
  final bool isLocal;

  @override
  State<DashboardUserItem> createState() => _DashboardUserItemState();
}

class _DashboardUserItemState extends State<DashboardUserItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final borderRadius = widget.grouped
        ? groupedTileBorderRadius(index: widget.index, count: widget.count)
        : AppRadius.brMedium;

    return RepaintBoundary(
      child: _UserTileShell(
        grouped: widget.grouped,
        index: widget.index,
        count: widget.count,
        borderRadius: borderRadius,
        isHovered: _isHovered,
        onHoverChanged: (v) => setState(() => _isHovered = v),
        onTap: () =>
            _copyIp(context, hasIpv4: node.hasValidIpv4, ipv4: node.ipv4),
        child: Padding(
          padding: EdgeInsets.fromLTRB(widget.grouped ? 16 : 12, 12, 12, 12),
          child: _UserMainContentRow(
            node: node,
            isLocal: widget.isLocal,
            nodeManagement: widget.nodeManagement,
            latencyColor: _latencyColor,
            compact: widget.compact,
            avatarWidget: _UserAvatar(avatar: widget.node.avatar),
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
      showAppToast(context, '该成员尚未分配 IP');
      return;
    }
    await Clipboard.setData(ClipboardData(text: ipv4));
    HapticFeedback.selectionClick();
    if (!context.mounted) return;
    showAppToast(context, '已复制 IP：$ipv4');
  }
}

String _formatMbps(double? value) {
  if (value == null) return '—';
  if (value >= 100) return value.toStringAsFixed(0);
  if (value >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}

/// 概要行：运营商 · 系统 · 网络 · 防火墙。
String _statusSummary(EnhancedNodeInfo node) {
  final os = OsPresentation.forNode(node);
  final network = NetworkPresentation.fromWire(node.peerNetwork);
  final firewall = FirewallPresentation.fromWire(node.peerFirewall);
  return [
    ?node.peerIsp,
    if (os.shortLabel.isNotEmpty) os.shortLabel,
    if (network.hasLabel) network.shortLabel,
    if (firewall.hasLabel) firewall.shortLabel,
  ].join(' · ');
}

/// Tooltip 完整文案。
String _peerClientEnvFull(EnhancedNodeInfo node) {
  final lines = <String>[];
  final os = node.peerOs;
  final osVer = node.peerOsVersion;
  if (os != null && os.isNotEmpty) {
    lines.add('系统: ${OsPresentation.humanizeOsKey(os)}');
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

// ─── 拆分后的子 Widget ───────────────────────────────────────────────────────

/// 用户头像：44pt 圆形，无描边，占位符使用中性底色。
class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.avatar});

  final Uint8List? avatar;

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final palette = context.astralPalette;
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.accentMuted,
      ),
      child: avatar != null
          ? ClipOval(
              child: Image.memory(
                avatar!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                cacheWidth: (size * dpr).round(),
                cacheHeight: (size * dpr).round(),
                gaplessPlayback: true,
              ),
            )
          : Icon(Icons.person_rounded, size: 24, color: palette.textTertiary),
    );
  }
}

/// 测速行：`测速 ↓916 ↑93.2 Mbps`，仅在丢包大于 0 时追加丢包。
class _UserSpeedLine extends StatelessWidget {
  const _UserSpeedLine({required this.node});

  final EnhancedNodeInfo node;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    if (!node.hasSpeedTest) {
      return Text(
        '未测速',
        style: TextStyle(fontSize: 12, color: palette.textTertiary),
      );
    }

    final loss = node.peerLossRate;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '测速 ',
            style: TextStyle(fontSize: 11.5, color: palette.textTertiary),
          ),
          TextSpan(
            text:
                '↓ ${_formatMbps(node.peerDownloadMbps)}   '
                '↑ ${_formatMbps(node.peerUploadMbps)} Mbps',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: palette.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (loss != null && loss > 0)
            TextSpan(
              text: '   ·   丢包 ${loss.toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.error,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 元信息行：IP · 直连/中转 · 应用版本，实时丢包仅在异常时出现。
class _UserMetaLine extends StatelessWidget {
  const _UserMetaLine({
    required this.node,
    required this.isLocal,
    required this.nodeManagement,
  });

  final EnhancedNodeInfo node;
  final bool isLocal;
  final NodeManagementService nodeManagement;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final hasIpv4 = node.hasValidIpv4;
    final hasIpv6 = node.hasValidIpv6;
    final isDirect = node.baseInfo.cost <= 1;
    final versionNumber = PlatformVersionParser.getVersionNumber(
      node.baseInfo.version,
    );

    return Watch((context) {
      final metrics = nodeManagement.linkMetricsOf(node.peerId).value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: hasIpv4 ? node.ipv4 : '未分配 IP',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasIpv4
                        ? palette.textSecondary
                        : palette.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (!isLocal)
                  TextSpan(
                    text: '   ${isDirect ? '直连' : '中转'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDirect ? AppColors.online : AppColors.warning,
                    ),
                  ),
                if (versionNumber.isNotEmpty)
                  TextSpan(
                    text: '   $versionNumber',
                    style: TextStyle(fontSize: 11, color: palette.textTertiary),
                  ),
                if (metrics.lossRate > 0)
                  TextSpan(
                    text: '   丢包 ${metrics.lossRate.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.error,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hasIpv6)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                node.ipv6,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: palette.textTertiary),
              ),
            ),
        ],
      );
    });
  }
}

/// 主内容行（头像 + 信息列）。
class _UserMainContentRow extends StatelessWidget {
  const _UserMainContentRow({
    required this.node,
    required this.isLocal,
    required this.nodeManagement,
    required this.latencyColor,
    required this.avatarWidget,
    required this.compact,
  });

  final EnhancedNodeInfo node;
  final bool isLocal;
  final NodeManagementService nodeManagement;
  final Color Function(double) latencyColor;
  final Widget avatarWidget;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final summary = compact ? '' : _statusSummary(node);
    final envFull = _peerClientEnvFull(node);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatarWidget,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            node.customName ?? '...',
                            style: TextStyle(
                              fontSize: 15.5,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: node.customName != null
                                  ? palette.textPrimary
                                  : palette.textTertiary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isLocal) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accentMuted,
                              borderRadius: AppRadius.brSmall,
                            ),
                            child: Text(
                              '本机',
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                                color: palette.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isLocal) ...[
                    const SizedBox(width: 8),
                    Watch((context) {
                      final metrics = nodeManagement
                          .linkMetricsOf(node.peerId)
                          .value;
                      return Text(
                        '${metrics.latencyMs.round()} ms',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: latencyColor(metrics.latencyMs),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      );
                    }),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              if (compact)
                Text(
                  node.hasValidIpv4 ? node.ipv4 : '未分配 IP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: node.hasValidIpv4
                        ? palette.textSecondary
                        : palette.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              else ...[
                if (summary.isNotEmpty) ...[
                  Tooltip(
                    message: envFull.isEmpty ? summary : envFull,
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                _UserSpeedLine(node: node),
                const SizedBox(height: 4),
                _UserMetaLine(
                  node: node,
                  isLocal: isLocal,
                  nodeManagement: nodeManagement,
                ),
              ],
            ],
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
    required this.child,
  });

  final bool grouped;
  final int index;
  final int count;
  final BorderRadius borderRadius;
  final bool isHovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final shape = grouped
        ? groupedTileShape(index: index, count: count)
        : RoundedRectangleBorder(borderRadius: borderRadius);

    // hover 只由外层 AnimatedContainer 绘制，InkWell 关闭所有默认覆盖色，
    // 否则 Material 默认灰会与自定义底色叠加，出现移入移出颜色突变。
    final ink = Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: grouped ? null : borderRadius,
        customBorder: grouped ? shape : null,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: palette.accent.withValues(alpha: 0.08),
        child: child,
      ),
    );

    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: grouped
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isHovered
              ? palette.accent.withValues(alpha: 0.055)
              : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: ink,
      ),
    );
  }
}
