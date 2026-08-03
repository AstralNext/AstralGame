import 'package:flutter/material.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/data/models/server_mod.dart';

import 'blocked_servers.dart';

Future<void> showAddServerDialog(BuildContext context) async {
  return showDialog(
    context: context,
    builder: (context) =>
        ServerDialog(title: '添加服务器', confirmText: '添加'),
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
  final String title;
  final String confirmText;
  final ServerMod? server;

  const ServerDialog({
    super.key,
    required this.title,
    required this.confirmText,
    this.server,
  });

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
    if (widget.server != null) {
      _nameController.text = widget.server!.name;
      _urlController.text = widget.server!.url;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _saveServer() {
    if (_formKey.currentState!.validate()) {
      final server = ServerMod(
        id: widget.server?.id,
        enable: widget.server?.enable ?? false,
        name: _nameController.text,
        url: _urlController.text,
        source: widget.server?.source ?? ServerSource.manual,
      );

      if (widget.server == null) {
        getIt<ServerState>().addServer(server);
      } else {
        getIt<ServerState>().updateServer(server);
      }
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '服务器名称',
                  hintText: '输入服务器名称',
                  border: const OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.dns, color: colorScheme.primary),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入服务器名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _urlController,
                enabled: widget.server == null ||
                    !BlockedServers.isBlocked(widget.server!.url),
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: '输入完整服务器地址，例如 tcp://example.com:11010',
                  border: const OutlineInputBorder(),
                  prefixIcon:
                      Icon(Icons.language, color: colorScheme.primary),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  helperText: widget.server != null &&
                          BlockedServers.isBlocked(widget.server!.url)
                      ? '此服务器地址不可修改'
                      : null,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入服务器地址';
                  }
                  final trimmed = value.trim();
                  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
                  if (!hasScheme) {
                    return '请输入完整地址（必须包含协议头），例如 tcp://example.com:11010';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _saveServer,
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}
