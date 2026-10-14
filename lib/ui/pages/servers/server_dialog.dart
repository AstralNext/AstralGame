import 'dart:async';

import 'package:flutter/material.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/server_probe_service.dart';

import 'blocked_servers.dart';

Future<void> showAddServerDialog(BuildContext context) async {
  return showDialog(
    context: context,
    builder: (context) => const ServerDialog(title: '添加服务器', confirmText: '添加'),
  );
}

Future<void> showEditServerDialog(
  BuildContext context, {
  required ServerMod server,
}) async {
  return showDialog(
    context: context,
    builder: (context) =>
        ServerDialog(title: '编辑服务器', confirmText: '保存', server: server),
  );
}

class ServerDialog extends StatefulWidget {
  const ServerDialog({
    super.key,
    required this.title,
    required this.confirmText,
    this.server,
  });
  final String title;
  final String confirmText;
  final ServerMod? server;

  @override
  State<ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<ServerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _probeService = ServerProbeService();
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.server;
    if (existing != null) {
      _nameController.text = existing.name;
      _urlController.text = existing.url;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _saveServer() async {
    if (!_formKey.currentState!.validate()) return;
    final server = ServerMod(
      id: widget.server?.id,
      enable: widget.server?.enable ?? false,
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      sortOrder: widget.server?.sortOrder ?? 0,
    );

    if (widget.server == null) {
      // 添加前先做一次「加入节点」探测，非 EasyTier 服务器需二次确认。
      setState(() => _probing = true);
      final result = await _probeService.probe(server);
      if (!mounted) return;
      setState(() => _probing = false);
      if (!result.isEasyTier && !await _confirmNonEasyTier(server.url)) return;
      if (!mounted) return;
      await getIt<ServerState>().addServer(server);
    } else {
      await getIt<ServerState>().updateServer(server);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 探测到非 ET 服务器时的二次确认；返回 true 表示仍要添加。
  Future<bool> _confirmNonEasyTier(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('非 EasyTier 服务器'),
        content: Text('检测到 "$url" 不是 EasyTier 服务器，可能无法正常联机。\n是否仍然继续添加？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续添加'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final urlLocked =
        widget.server != null && BlockedServers.isBlocked(widget.server!.url);

    return AlertDialog(
      // 窄屏收紧默认 insetPadding（左右各 40 太浪费），给输入框留出宽度
      insetPadding: MediaQuery.sizeOf(context).width < 600
          ? const EdgeInsets.symmetric(horizontal: 20, vertical: 24)
          : null,
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '填写名称与地址即可。启用后会写入 EasyTier [[peer]]。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '例如：家里节点',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入名称';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _urlController,
                  enabled: !urlLocked,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => unawaited(_saveServer()),
                  decoration: InputDecoration(
                    labelText: '地址',
                    hintText: 'tcp://192.168.1.10:11010',
                    helperText: urlLocked
                        ? '此地址不可修改'
                        : '须含协议，如 tcp:// 或 udp://',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入地址';
                    }
                    final trimmed = value.trim();
                    final hasScheme = RegExp(
                      r'^[a-zA-Z][a-zA-Z0-9+.-]*://',
                    ).hasMatch(trimmed);
                    if (!hasScheme) {
                      return '请输入完整地址，例如 tcp://example.com:11010';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _probing ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _probing ? null : () => unawaited(_saveServer()),
          child: _probing
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('检测中…'),
                  ],
                )
              : Text(widget.confirmText),
        ),
      ],
    );
  }
}
