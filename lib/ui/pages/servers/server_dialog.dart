import 'package:flutter/material.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/data/models/server_mod.dart';

import 'blocked_servers.dart';

Future<void> showAddServerDialog(BuildContext context) async {
  return showDialog(
    context: context,
    builder: (context) =>
        const ServerDialog(title: '添加服务器', confirmText: '添加'),
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

  void _saveServer() {
    if (!_formKey.currentState!.validate()) return;
    final server = ServerMod(
      id: widget.server?.id,
      enable: widget.server?.enable ?? false,
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      sortOrder: widget.server?.sortOrder ?? 0,
    );

    if (widget.server == null) {
      getIt<ServerState>().addServer(server);
    } else {
      getIt<ServerState>().updateServer(server);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final urlLocked = widget.server != null &&
        BlockedServers.isBlocked(widget.server!.url);

    return AlertDialog(
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
                  onFieldSubmitted: (_) => _saveServer(),
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
                    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://')
                        .hasMatch(trimmed);
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saveServer,
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}
