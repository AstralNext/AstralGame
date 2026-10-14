import 'dart:async';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/ui/widgets/app_snack_bar.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/utils/runtime_platform.dart';

import 'server_dialog.dart';
import 'blocked_servers.dart';

class ServersMainPage extends StatefulWidget {
  const ServersMainPage({super.key});

  @override
  State<ServersMainPage> createState() => _ServersMainPageState();
}

class _ServersMainPageState extends State<ServersMainPage> {
  final _serverState = getIt<ServerState>();
  final _serverStatusState = getIt<ServerStatusState>();
  String? _lastServersFingerprint;
  bool _pingActive = false;

  @override
  void dispose() {
    _serverStatusState.stopPeriodicCheck();
    super.dispose();
  }

  Color _getStatusColor(ServerStatus status, ColorScheme colorScheme) {
    switch (status) {
      case ServerStatus.online:
        return AppColors.online;
      case ServerStatus.offline:
        return AppColors.error;
      case ServerStatus.inUse:
        return AppColors.info;
      case ServerStatus.unknown:
        return colorScheme.outline;
    }
  }

  Color _getLatencyColor(int latencyMs, ColorScheme colorScheme) {
    if (latencyMs <= 80) return AppColors.online;
    if (latencyMs <= 160) return Colors.orange;
    return AppColors.error;
  }

  /// 探测结果行（探测中 / EasyTier 版本 / 非 ET 警告），统一小字号。
  Widget _buildProbeStatus(
    BuildContext context,
    Widget child, {
    bool isWarning = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
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
                color: isWarning ? AppColors.error : colorScheme.outline,
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

  /// 手动「检测」：对全部服务器各做一次「加入节点」探测，非 ET 服务器弹警告。
  Future<void> _handleProbe(BuildContext context) async {
    await _serverStatusState.probeServers(_serverState.servers.value);
    if (!context.mounted) return;
    final nonEtCount = _serverStatusState.serverProbes.value.values
        .where((p) => !p.isEasyTier)
        .length;
    if (nonEtCount > 0) {
      showAppSnackBar(
        context,
        '$nonEtCount 个服务器不是 EasyTier 服务器',
        duration: const Duration(seconds: 3),
      );
    }
  }

  Widget _buildBody(BuildContext context, {required bool visible}) {
    return Watch((context) {
      final servers = _serverState.servers.value;
      final statuses = _serverStatusState.serverStatuses.value;
      final latencies = _serverStatusState.serverLatencies.value;
      final probes = _serverStatusState.serverProbes.value;
      final probingIds = _serverStatusState.probingServerIds.value;

      if (visible) {
        final fingerprint = servers
            .map((s) => '${s.id}:${s.url}:${s.enable}')
            .join('|');
        if (_lastServersFingerprint != fingerprint) {
          _lastServersFingerprint = fingerprint;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _serverStatusState.startPeriodicCheck(
              _serverState.servers.value,
              AppConstants.serverPingInterval,
            );
            _pingActive = true;
          });
        }
      }

      if (servers.isEmpty) {
        return EmptyState(
          icon: Icons.dns_outlined,
          title: '暂无服务器',
          actionLabel: '添加服务器',
          actionStyle: EmptyActionStyle.filled,
          actionIcon: Icons.add,
          onAction: () => showAddServerDialog(context),
        );
      }

      final anyProbing = probingIds.isNotEmpty;
      // 与全站一致的 600 断点；窄屏收紧左右边距，给内容更多横向空间。
      final isNarrow = MediaQuery.sizeOf(context).width < 600;
      final hPad = isNarrow ? 12.0 : AppDimensions.pagePaddingH;
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              hPad,
              AppDimensions.pagePaddingV,
              hPad,
              0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.tonalIcon(
                  onPressed: anyProbing ? null : () => _handleProbe(context),
                  icon: anyProbing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: Text(anyProbing ? '检测中' : '检测'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: EdgeInsets.fromLTRB(
                hPad,
                AppDimensions.sectionGap,
                hPad,
                88,
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
                final colorScheme = Theme.of(context).colorScheme;
                final addressLine = BlockedServers.isBlocked(server.url)
                    ? '***'
                    : server.url;
                final statusColor = probing
                    ? AppColors.info
                    : latency != null
                    ? _getLatencyColor(latency, colorScheme)
                    : _getStatusColor(status, colorScheme);
                // 手机不展示服务器地址（IP 对玩家没意义，界面也更干净）；
                // 名称本身就是地址时也没必要再把同一串显示两遍。
                final showAddress =
                    !RuntimePlatform.isMobile &&
                    server.name.trim().toLowerCase() !=
                        addressLine.trim().toLowerCase();

                // 卡片：左侧信息列（名称 / 地址 / 延迟+探测），右侧开关垂直居中。
                // 触屏端编辑、删除走侧滑；桌面端用「更多」菜单。
                final card = Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AstralCard(
                    padding: EdgeInsets.zero,
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
                                        borderRadius: BorderRadius.circular(2),
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
                                // 地址独占一整行（手机上不显示）
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
                                            color: colorScheme.outline,
                                          ),
                                    ),
                                  ),
                                // 延迟 + 探测状态同一行，放不下时探测文案自己省略
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 14,
                                    top: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      if (probing)
                                        const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      else
                                        Text(
                                          latency != null
                                              ? '${latency}ms'
                                              : '--',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: colorScheme.outline,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      if (probing || probe != null) ...[
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: probing
                                              ? _buildProbeStatus(
                                                  context,
                                                  const Text('探测中…'),
                                                )
                                              : _buildProbeStatus(
                                                  context,
                                                  probe!.isEasyTier
                                                      ? Text(
                                                          'EasyTier '
                                                          '${probe.version}'
                                                          ' · 协议 '
                                                          'v${probe.protocolVersion}',
                                                        )
                                                      : const Text(
                                                          '非 EasyTier 服务器',
                                                        ),
                                                  isWarning: !probe.isEasyTier,
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
                            PopupMenuButton<String>(
                              tooltip: '更多操作',
                              iconSize: 20,
                              padding: const EdgeInsets.all(4),
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
                        ],
                      ),
                    ),
                  ),
                );

                // 触屏长按拖拽，避免与列表滚动抢手势；桌面端鼠标可直接拖。
                final draggable = RuntimePlatform.isDesktop
                    ? ReorderableDragStartListener(
                        key: ValueKey(server.id),
                        index: index,
                        child: card,
                      )
                    : ReorderableDelayedDragStartListener(
                        key: ValueKey(server.id),
                        index: index,
                        child: card,
                      );
                if (!RuntimePlatform.isMobile) return draggable;

                // 手机：右滑编辑、左滑删除（删除前确认），替代桌面端的「更多」菜单
                return Dismissible(
                  key: ValueKey('server-swipe-${server.id}'),
                  background: _swipeActionHint(context, edit: true),
                  secondaryBackground: _swipeActionHint(context, edit: false),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.startToEnd) {
                      _openEditDialog(context, server);
                      return false;
                    }
                    return _confirmDelete(server);
                  },
                  onDismissed: (_) => _serverState.removeServer(server.id),
                  child: draggable,
                );
              },
            ),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = TickerMode.valuesOf(context).enabled;
    if (!visible && _pingActive) {
      _serverStatusState.stopPeriodicCheck();
      _pingActive = false;
      _lastServersFingerprint = null;
    }
    return Scaffold(
      body: _buildBody(context, visible: visible),
      floatingActionButton: FloatingActionButton(
        heroTag: 'add_server',
        tooltip: '添加服务器',
        onPressed: () => showAddServerDialog(context),
        child: const Icon(Icons.add),
      ),
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

  /// 侧滑时露出的提示块：右滑编辑 / 左滑删除。
  Widget _swipeActionHint(BuildContext context, {required bool edit}) {
    final scheme = Theme.of(context).colorScheme;
    final color = edit ? scheme.primary : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: edit ? Alignment.centerLeft : Alignment.centerRight,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            edit ? Icons.edit_outlined : Icons.delete_outline,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            edit ? '编辑' : '删除',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// 桌面端「更多操作」菜单里的编辑 / 删除两项（触屏端改用侧滑）。
  List<PopupMenuEntry<String>> _serverMenuItems(
    BuildContext context,
    ServerMod server,
  ) {
    final isBlocked = BlockedServers.isBlocked(server.url);
    final scheme = Theme.of(context).colorScheme;
    return [
      PopupMenuItem(
        value: 'edit',
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
      showAppSnackBar(
        context,
        '此服务器不可编辑',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    showEditServerDialog(context, server: server);
  }
}
