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

  Widget _buildBody(BuildContext context, {required bool visible}) {
    return Watch((context) {
      final servers = _serverState.servers.value;
      final statuses = _serverStatusState.serverStatuses.value;
      final latencies = _serverStatusState.serverLatencies.value;

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

      return ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppDimensions.pagePaddingH,
          AppDimensions.pagePaddingV,
          AppDimensions.pagePaddingH,
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
          final colorScheme = Theme.of(context).colorScheme;
          final addressLine = BlockedServers.isBlocked(server.url)
              ? '***'
              : server.url;
          final subtitleText = addressLine;

          return ReorderableDragStartListener(
            key: ValueKey(server.id),
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AstralCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: SizedBox(
                    width: 56,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 4,
                          height: 40,
                          decoration: BoxDecoration(
                            color: latency != null
                                ? _getLatencyColor(latency, colorScheme)
                                : _getStatusColor(status, colorScheme),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            latency != null ? '${latency}ms' : '--',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: colorScheme.outline,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  title: Text(
                    server.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    subtitleText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: server.enable,
                          onChanged: (value) {
                            _serverState.toggleServerEnabled(server.id, value);
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            if (BlockedServers.isBlocked(server.url)) {
                              showAppSnackBar(
                                context,
                                '此服务器不可编辑',
                                duration: const Duration(seconds: 2),
                              );
                            } else {
                              showEditServerDialog(context, server: server);
                            }
                          } else if (value == 'delete') {
                            _showDeleteConfirmDialog(server);
                          }
                        },
                        itemBuilder: (context) {
                          final isBlocked = BlockedServers.isBlocked(
                            server.url,
                          );
                          final scheme = Theme.of(context).colorScheme;
                          return [
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: isBlocked
                                        ? scheme.outline
                                        : scheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '编辑',
                                    style: TextStyle(
                                      color: isBlocked ? scheme.outline : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: scheme.error,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '删除',
                                    style: TextStyle(color: scheme.error),
                                  ),
                                ],
                              ),
                            ),
                          ];
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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

  void _showDeleteConfirmDialog(ServerMod server) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定要删除服务器 "${server.name}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              _serverState.removeServer(server.id);
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
