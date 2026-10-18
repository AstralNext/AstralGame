import 'dart:async';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/app_toast.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/empty_state.dart';
import 'package:astral_game/ui/widgets/glass_icon_button.dart';
import 'package:astral_game/ui/widgets/grouped_tile_shape.dart';
import 'package:astral_game/ui/widgets/page_header.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/utils/runtime_platform.dart';

import 'server_dialog.dart';
import 'blocked_servers.dart';

/// 手动「检测」：对全部服务器各做一次「加入节点」探测，非 ET 服务器弹警告。
///
/// 悬浮底栏的刷新操作与下拉刷新共用这一入口。
Future<void> probeAllServers(BuildContext context) async {
  final serverState = getIt<ServerState>();
  final serverStatusState = getIt<ServerStatusState>();
  await serverStatusState.probeServers(serverState.servers.value);
  if (!context.mounted) return;
  final nonEtCount = serverState.servers.value
      .where((s) => s.enable)
      .where(
        (s) => serverStatusState.serverProbes.value[s.id]?.isEasyTier == false,
      )
      .length;
  if (nonEtCount > 0) {
    showAppToast(
      context,
      '$nonEtCount 个服务器不是 EasyTier 服务器',
      duration: const Duration(seconds: 3),
    );
  }
}

class ServersMainPage extends StatefulWidget {
  const ServersMainPage({super.key});

  @override
  State<ServersMainPage> createState() => _ServersMainPageState();
}

class _ServersMainPageState extends State<ServersMainPage> {
  final _serverState = getIt<ServerState>();
  final _serverStatusState = getIt<ServerStatusState>();
  String? _lastServersFingerprint;

  Color _getStatusColor(BuildContext context, ServerStatus status) {
    switch (status) {
      case ServerStatus.online:
        return AppColors.online;
      case ServerStatus.offline:
        return AppColors.error;
      case ServerStatus.inUse:
        return AppColors.info;
      case ServerStatus.unknown:
        return context.astralPalette.textTertiary;
    }
  }

  Color _getLatencyColor(int latencyMs) {
    if (latencyMs <= 80) return AppColors.online;
    if (latencyMs <= 160) return AppColors.warning;
    return AppColors.error;
  }

  String _statusLabel(ServerStatus status) {
    switch (status) {
      case ServerStatus.online:
        return '在线';
      case ServerStatus.offline:
        return '离线';
      case ServerStatus.inUse:
        return '使用中';
      case ServerStatus.unknown:
        return '未检测';
    }
  }

  /// 页头「上次检测」的短时间格式。
  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// 探测结果行（探测中 / EasyTier 版本 / 非 ET 警告），统一小字号。
  Widget _buildProbeStatus(
    BuildContext context,
    Widget child, {
    bool isWarning = false,
  }) {
    final palette = context.astralPalette;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isWarning) ...[
            const Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: AppColors.error,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isWarning ? AppColors.error : palette.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  /// 宽屏页头右侧：玻璃刷新圆钮 + 主色「添加」胶囊。
  ///
  /// 与手机端悬浮底栏的行动胶囊一一对应，只是换成桌面更合适的图标按钮。
  List<Widget> _buildHeaderActions(
    BuildContext context, {
    required bool probing,
  }) {
    final palette = context.astralPalette;
    return [
      GlassIconButton(
        size: AppDimensions.iconButtonSize,
        tooltip: probing ? '正在检测' : '重新检测并测速',
        semanticsLabel: probing ? '正在检测' : '重新检测并测速',
        onPressed: probing ? null : () => unawaited(probeAllServers(context)),
        child: probing
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.accent,
                ),
              )
            : Icon(Icons.refresh_rounded, size: 20, color: palette.textPrimary),
      ),
      const SizedBox(width: 8),
      SizedBox(
        height: AppDimensions.iconButtonSize,
        child: Material(
          color: palette.accent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: () => showAddServerDialog(context),
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 18, color: palette.onAccent),
                  const SizedBox(width: 4),
                  Text(
                    '添加',
                    style: TextStyle(
                      color: palette.onAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildBody(BuildContext context) {
    return Watch((context) {
      final servers = _serverState.servers.value;
      final statuses = _serverStatusState.serverStatuses.value;
      final latencies = _serverStatusState.serverLatencies.value;
      final probes = _serverStatusState.serverProbes.value;
      final probingIds = _serverStatusState.probingServerIds.value;

      // 仅在本地丢弃过期结果，不做任何自动探测。
      final fingerprint = servers
          .map((s) => '${s.id}:${s.url}:${s.enable}')
          .join('|');
      if (_lastServersFingerprint != fingerprint) {
        _lastServersFingerprint = fingerprint;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _serverStatusState.invalidateStaleProbes(_serverState.servers.value);
        });
      }

      // 与全站一致的窄屏断点；窄屏收紧左右边距，给内容更多横向空间。
      final isNarrow = MediaQuery.sizeOf(context).width < AppBreakpoints.narrow;
      final hPad = isNarrow
          ? AppDimensions.pagePaddingHMobile
          : AppDimensions.pagePaddingH;
      final lastProbeAt = _serverStatusState.lastProbeAt.value;
      final onlineCount = servers.where((server) {
        final status = statuses[server.id];
        return status == ServerStatus.online || status == ServerStatus.inUse;
      }).length;
      // 刷新与添加在手机端移入悬浮底栏右侧行动胶囊；宽屏没有底栏，
      // 放回页头右侧，与手机端保持同一套动作语义。
      final header = PageHeader(
        horizontalPadding: hPad,
        subtitle: servers.isEmpty
            ? '还没有添加服务器'
            : '${servers.length} 台 · $onlineCount 在线 · '
                  '${lastProbeAt == null ? '尚未检测' : '上次检测 ${_formatTime(lastProbeAt)}'}',
        actions: isNarrow || servers.isEmpty
            ? const []
            : _buildHeaderActions(context, probing: probingIds.isNotEmpty),
      );

      if (servers.isEmpty) {
        return Column(
          children: [
            header,
            Expanded(
              child: EmptyState(
                icon: Icons.dns_outlined,
                title: '暂无服务器',
                subtitle: '添加一台服务器后即可开始联机',
                actionLabel: '添加服务器',
                actionStyle: EmptyActionStyle.filled,
                actionIcon: Icons.add,
                onAction: () => showAddServerDialog(context),
              ),
            ),
          ],
        );
      }

      return Column(
        children: [
          header,
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => probeAllServers(context),
              child: ReorderableListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  hPad,
                  AppDimensions.sectionGap,
                  hPad,
                  // 内容延伸到屏幕底部：为悬浮胶囊留出余量。
                  isNarrow
                      ? AppDimensions.listBottomWithNav
                      : AppDimensions.listBottomWithFab,
                ),
                itemCount: servers.length,
                buildDefaultDragHandles: false,
                proxyDecorator: (child, index, animation) {
                  return Material(color: Colors.transparent, child: child);
                },
                // onReorderItem（Flutter 3.44+）：newIndex 已自动扣除 oldIndex 删除影响，无需手动调整。
                // CI 的 FLUTTER_VERSION 已钉在 3.47.2。
                onReorderItem: (oldIndex, newIndex) {
                  final newServers = List<ServerMod>.from(servers);
                  final server = newServers.removeAt(oldIndex);
                  newServers.insert(newIndex, server);
                  _serverState.reorderServers(newServers);
                },
                itemBuilder: (context, index) {
                  final server = servers[index];
                  final status = statuses[server.id] ?? ServerStatus.unknown;
                  final latency = latencies[server.id];
                  final probe = probes[server.id];
                  final probing = probingIds.contains(server.id);
                  final palette = context.astralPalette;
                  final addressLine = BlockedServers.isBlocked(server.url)
                      ? '***'
                      : server.url;
                  final statusColor = probing
                      ? AppColors.info
                      : latency != null
                      ? _getLatencyColor(latency)
                      : _getStatusColor(context, status);
                  // 名称本身就是地址时没必要再把同一串显示两遍。
                  final showAddress =
                      server.name.trim().toLowerCase() !=
                      addressLine.trim().toLowerCase();

                  // 卡片：左侧信息列（名称 / 地址 / 延迟+探测），右侧开关垂直居中。
                  // 手机点卡片打开操作面板；桌面端用「更多」菜单。
                  final card = Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AstralCard(
                      padding: EdgeInsets.zero,
                      onTap: RuntimePlatform.isMobile
                          ? () => _showActionsSheet(
                              context,
                              server: server,
                              status: status,
                              latency: latency,
                              probing: probing,
                            )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          server.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // 地址独占一整行
                                  if (showAddress)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 14,
                                        top: 4,
                                      ),
                                      child: Text(
                                        addressLine,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: palette.textSecondary,
                                            ),
                                      ),
                                    ),
                                  // 延迟 · 状态 + 探测结果同一行，放不下时探测文案自己省略
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 14,
                                      top: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        if (probing) ...[
                                          const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '检测中…',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  color: AppColors.info,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ] else
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: latency == null
                                                      ? '--'
                                                      : '${latency}ms',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        color: palette
                                                            .textSecondary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                                TextSpan(
                                                  text: ' · ',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        color: palette
                                                            .textTertiary,
                                                      ),
                                                ),
                                                TextSpan(
                                                  text: _statusLabel(status),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                        color: statusColor,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (probe?.isEasyTier != null) ...[
                                          const SizedBox(width: 10),
                                          Flexible(
                                            child: _buildProbeStatus(
                                              context,
                                              probe!.isEasyTier!
                                                  ? const Text('EasyTier')
                                                  : const Text(
                                                      '非 EasyTier 服务器',
                                                    ),
                                              isWarning: !probe.isEasyTier!,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            // 相对整张卡片垂直居中
                            Switch(
                              value: server.enable,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (value) {
                                _serverState.toggleServerEnabled(
                                  server.id,
                                  value,
                                );
                              },
                            ),
                            // 触屏用侧滑，不再放菜单
                            if (RuntimePlatform.isDesktop)
                              SizedBox(
                                width: AppDimensions.iconButtonSize,
                                height: AppDimensions.iconButtonSize,
                                child: PopupMenuButton<String>(
                                  tooltip: '更多操作',
                                  iconSize: 20,
                                  padding: EdgeInsets.zero,
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openEditDialog(context, server);
                                    } else if (value == 'delete') {
                                      unawaited(_handleDelete(server));
                                    }
                                  },
                                  itemBuilder: (context) =>
                                      _serverMenuItems(context, server),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );

                  // 触屏长按拖拽，避免与列表滚动抢手势；桌面端鼠标可直接拖。
                  final draggable = RuntimePlatform.isDesktop
                      ? ReorderableDragStartListener(index: index, child: card)
                      : ReorderableDelayedDragStartListener(
                          index: index,
                          child: card,
                        );
                  // ReorderableListView 要求每个 item 的最外层 widget 带 key，
                  // 因此 key 必须放在 Semantics 这一层，而不是内部的拖拽监听器上。
                  if (!RuntimePlatform.isMobile) {
                    return KeyedSubtree(
                      key: ValueKey(server.id),
                      child: draggable,
                    );
                  }

                  // 手机：点按打开底部操作面板，长按仍是拖动排序。
                  return Semantics(
                    key: ValueKey(server.id),
                    container: true,
                    label: '${server.name}，${_statusLabel(status)}',
                    hint: '点按打开操作面板，长按拖动排序',
                    child: draggable,
                  );
                },
              ),
            ),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _buildBody(context));
  }

  /// 手机操作面板：点卡片打开，低频操作排成整行可点的列表。
  Future<void> _showActionsSheet(
    BuildContext context, {
    required ServerMod server,
    required ServerStatus status,
    required int? latency,
    required bool probing,
  }) async {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final statusColor = probing
        ? AppColors.info
        : latency != null
        ? _getLatencyColor(latency)
        : _getStatusColor(context, status);
    final address = BlockedServers.isBlocked(server.url) ? '***' : server.url;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: palette.background,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        void run(VoidCallback action) {
          Navigator.of(sheetContext).pop();
          action();
        }

        final items =
            <({IconData icon, String label, VoidCallback onTap, bool danger})>[
              (
                icon: Icons.power_settings_new_rounded,
                label: server.enable ? '停用服务器' : '启用服务器',
                onTap: () => run(
                  () => _serverState.toggleServerEnabled(
                    server.id,
                    !server.enable,
                  ),
                ),
                danger: false,
              ),
              (
                icon: Icons.delete_outline_rounded,
                label: '删除服务器',
                onTap: () => run(() => _handleDelete(server)),
                danger: true,
              ),
            ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: palette.accentMuted,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.dns_rounded,
                      size: 26,
                      color: palette.accent,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.name,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: palette.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          address,
                          style: textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          probing
                              ? '检测中…'
                              : '${latency == null ? '--' : '${latency}ms'}'
                                    ' · ${_statusLabel(status)}',
                          style: textTheme.labelSmall?.copyWith(
                            color: probing ? AppColors.info : statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => run(() => _openEditDialog(context, server)),
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  label: const Text('编辑服务器'),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.onAccent,
                    textStyle: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AstralCard(
                padding: EdgeInsets.zero,
                shadow: false,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      ListTile(
                        shape: groupedTileShape(index: i, count: items.length),
                        leading: Icon(
                          items[i].icon,
                          size: 22,
                          color: items[i].danger
                              ? palette.error
                              : palette.accent,
                        ),
                        title: Text(
                          items[i].label,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: items[i].danger
                                ? palette.error
                                : palette.textPrimary,
                          ),
                        ),
                        onTap: items[i].onTap,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 删除确认；返回 true 表示用户确认删除。
  Future<bool> _confirmDelete(ServerMod server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定要删除服务器 "${server.name}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// 桌面端「更多」菜单的删除入口（触屏端走侧滑）。
  Future<void> _handleDelete(ServerMod server) async {
    if (await _confirmDelete(server)) {
      _serverState.removeServer(server.id);
    }
  }

  /// 桌面端「更多操作」菜单里的编辑 / 删除两项（触屏端改用操作面板）。
  List<PopupMenuEntry<String>> _serverMenuItems(
    BuildContext context,
    ServerMod server,
  ) {
    final isBlocked = BlockedServers.isBlocked(server.url);
    final scheme = Theme.of(context).colorScheme;
    return [
      PopupMenuItem(
        value: 'edit',
        enabled: !isBlocked,
        child: Row(
          children: [
            Icon(
              Icons.edit_outlined,
              size: 18,
              color: isBlocked ? scheme.outline : scheme.primary,
            ),
            const SizedBox(width: 12),
            Text(
              '编辑',
              style: TextStyle(color: isBlocked ? scheme.outline : null),
            ),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 18, color: scheme.error),
            const SizedBox(width: 12),
            Text('删除', style: TextStyle(color: scheme.error)),
          ],
        ),
      ),
    ];
  }

  /// 编辑服务器；被拦截的内置服务器不允许改，提示一下即可。
  void _openEditDialog(BuildContext context, ServerMod server) {
    if (BlockedServers.isBlocked(server.url)) {
      showAppToast(context, '此服务器不可编辑', duration: const Duration(seconds: 2));
      return;
    }
    showEditServerDialog(context, server: server);
  }
}
