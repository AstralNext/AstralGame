import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/public_server_service.dart';
import 'package:astral_game/utils/ping_util.dart';

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

  @override
  void initState() {
    super.initState();
    // 延迟检测会在 build 的 Watch 中根据服务器列表自动刷新
  }

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
    // 颜色分段可按需要再微调
    if (latencyMs <= 80) return AppColors.online;
    if (latencyMs <= 160) return Colors.orange;
    return AppColors.error;
  }

  String _sourceLabel(ServerSource source) {
    switch (source) {
      case ServerSource.public:
        return '公共服务器';
      case ServerSource.manual:
        return '手动添加';
    }
  }

  Widget _buildBody(BuildContext context) {
    return Watch((context) {
      final servers = _serverState.servers.value;
      final statuses = _serverStatusState.serverStatuses.value;
      final latencies = _serverStatusState.serverLatencies.value;

      // 服务器列表是 signal，会动态变化；这里确保延迟检测的目标列表始终是最新的。
      final fingerprint =
          servers.map((s) => '${s.id}:${s.url}:${s.enable}').join('|');
      if (_lastServersFingerprint != fingerprint) {
        _lastServersFingerprint = fingerprint;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _serverStatusState.startPeriodicCheck(
            _serverState.servers.value,
            const Duration(seconds: 30),
          );
        });
      }

      if (servers.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.dns_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                '暂无服务器',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => showAddServerDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('添加服务器'),
              ),
            ],
          ),
        );
      }

      return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.pagePaddingH,
        AppDimensions.pagePaddingV,
        AppDimensions.pagePaddingH,
        24,
      ),
      itemCount: servers.length,
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) {
        return Material(
          elevation: 0,
          color: Colors.transparent,
          child: child,
        );
      },
      onReorder: (oldIndex, newIndex) {
        final newServers = List<ServerMod>.from(servers);
        if (oldIndex < newIndex) {
          newIndex -= 1;
        }
        final server = newServers.removeAt(oldIndex);
        newServers.insert(newIndex, server);
        _serverState.reorderServers(newServers);
      },
      itemBuilder: (context, index) {
        final server = servers[index];
        final status = statuses[server.id] ?? ServerStatus.unknown;
        final latency = latencies[server.id];
        final colorScheme = Theme.of(context).colorScheme;

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
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: colorScheme.outline,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      server.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: server.source == ServerSource.public
                          ? colorScheme.primary.withValues(alpha: 0.10)
                          : colorScheme.outline.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _sourceLabel(server.source),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: server.source == ServerSource.public
                                ? colorScheme.primary
                                : colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                server.source == ServerSource.public
                    ? '公共服务器'
                    : (BlockedServers.isBlocked(server.url) ? '***' : server.url),
                maxLines: 1,
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
                        if (BlockedServers.isBlocked(server.url) ||
                            server.source == ServerSource.public) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('此服务器不可编辑'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        } else {
                          showEditServerDialog(context, server: server);
                        }
                      } else if (value == 'delete') {
                        _showDeleteConfirmDialog(server);
                      }
                    },
                    itemBuilder: (context) {
                      final isBlocked =
                          BlockedServers.isBlocked(server.url);
                      final colorScheme = Theme.of(context).colorScheme;
                      return [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: isBlocked
                                    ? colorScheme.outline
                                    : colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '编辑',
                                style: TextStyle(
                                  color:
                                      isBlocked ? colorScheme.outline : null,
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
                                color: colorScheme.error,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '删除',
                                style:
                                    TextStyle(color: colorScheme.error),
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
    return Scaffold(
      body: _buildBody(context),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'public_servers',
            onPressed: () => _showPublicServersDialog(context),
            child: const Icon(Icons.public),
          ),
          const SizedBox(width: 16),
          FloatingActionButton(
            heroTag: 'add_server',
            onPressed: () => showAddServerDialog(context),
            child: const Icon(Icons.add),
          ),
        ],
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

  void _showPublicServersDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _PublicServerDialog(
        serverState: _serverState,
      ),
    );
  }
}

class _PublicServerDialog extends StatefulWidget {
  final ServerState serverState;

  const _PublicServerDialog({required this.serverState});

  @override
  State<_PublicServerDialog> createState() => _PublicServerDialogState();
}

class _PublicServerDialogState extends State<_PublicServerDialog> {
  final _service = PublicServerService();
  List<PublicServer> _servers = [];
  bool _isLoading = true;
  String? _error;
  final Map<String, int?> _latencies = {};

  Color _getLatencyColor(int latencyMs, ColorScheme colorScheme) {
    if (latencyMs <= 80) return AppColors.online;
    if (latencyMs <= 160) return Colors.orange;
    return AppColors.error;
  }

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _latencies.clear();
    });

    try {
      final servers = await _service.fetchServers();
      if (mounted) {
        setState(() {
          _servers = servers;
          _isLoading = false;
        });
      }

      // 后台测延迟（解密后的明文 URL）
      for (final s in servers) {
        final url = (s.decryptedUrl ?? '').trim();
        if (url.isEmpty) continue;
        PingUtil.ping(url).then((ms) {
          if (!mounted) return;
          setState(() {
            _latencies[url] = ms;
          });
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  bool _isAlreadyAdded(PublicServer server) {
    final url = (server.decryptedUrl ?? '').trim();
    if (url.isEmpty) return false;
    return widget.serverState.servers.value.any((s) => s.url.trim() == url);
  }

  void _addServer(PublicServer server) {
    final url = (server.decryptedUrl ?? '').trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('服务器地址解密失败，无法添加')),
      );
      return;
    }
    widget.serverState.addServer(
      ServerMod(
        name: server.name,
        url: url,
        enable: true,
        source: ServerSource.public,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加 "${server.name}"')),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('公共服务器'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: colorScheme.error)),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loadServers,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : _servers.isEmpty
                    ? const Center(child: Text('暂无公共服务器'))
                    : ListView.builder(
                        itemCount: _servers.length,
                        itemBuilder: (context, index) {
                          final server = _servers[index];
                          final added = _isAlreadyAdded(server);
                          final url = (server.decryptedUrl ?? '').trim();
                          final ms = url.isEmpty ? null : _latencies[url];

                          return Padding(
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
                                        color: ms != null
                                            ? _getLatencyColor(ms, colorScheme)
                                            : colorScheme.outline,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        ms != null ? '${ms}ms' : '--',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: colorScheme.outline,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              title: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      server.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary
                                          .withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '公共服务器',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: const Text(
                                '公共服务器',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: added
                                  ? Icon(Icons.check_circle,
                                      color: colorScheme.outline)
                                  : FilledButton.tonal(
                                      onPressed: () => _addServer(server),
                                      child: const Text('添加'),
                                    ),
                            ),
                            ),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
