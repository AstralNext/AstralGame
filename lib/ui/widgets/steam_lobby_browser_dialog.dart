import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/src/rust/api/steam.dart' as rust_steam;
import 'package:astral_game/ui/widgets/app_toast.dart';
import 'package:flutter/material.dart';

/// Steam 大厅搜房：按游戏筛选，选中后直接进房。
///
/// 过滤与版本校验在 Rust 侧完成（服务端 `ag_game` 字符串过滤 + 本地二次校验），
/// 这里只负责展示、收额外密码和调用进房。
Future<ActiveRoomSession?> showSteamLobbyBrowser(
  BuildContext context, {
  required ConnectionService connection,
  required List<GameInfo> catalog,
}) {
  return showDialog<ActiveRoomSession>(
    context: context,
    barrierColor: astralDialogBarrierColor,
    builder: (context) => _SteamLobbyBrowserDialog(
      connection: connection,
      catalog: catalog,
    ),
  );
}

class _SteamLobbyBrowserDialog extends StatefulWidget {
  const _SteamLobbyBrowserDialog({
    required this.connection,
    required this.catalog,
  });

  final ConnectionService connection;
  final List<GameInfo> catalog;

  @override
  State<_SteamLobbyBrowserDialog> createState() =>
      _SteamLobbyBrowserDialogState();
}

class _SteamLobbyBrowserDialogState extends State<_SteamLobbyBrowserDialog> {
  late GameInfo _game;
  List<rust_steam.SteamLobbyInfo> _rooms = const [];
  bool _loading = true;
  String? _error;
  String? _joiningLobbyId;

  @override
  void initState() {
    super.initState();
    _game = widget.catalog.first;
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rooms =
          await widget.connection.steamTransport.searchLobbies(_game.id);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _join(rust_steam.SteamLobbyInfo room) async {
    if (_joiningLobbyId != null) return;
    String? extra;
    if (room.gate == kSteamLobbyGateDouble) {
      extra = await _askExtraPassword(room);
      if (extra == null) return;
    } else if (room.gate == kSteamLobbyGateOpen) {
      final ok = await _confirmOpen(room);
      if (ok != true) return;
    }
    setState(() => _joiningLobbyId = room.lobbyId);
    try {
      final session = await widget.connection.joinSteamLobby(
        lobbyId: room.lobbyId,
        gameId: _game.id,
        gameName: _game.displayName,
        extraPassword: extra,
      );
      if (!mounted) return;
      Navigator.pop(context, session);
    } catch (e) {
      if (!mounted) return;
      setState(() => _joiningLobbyId = null);
      showAppToast(context, '$e');
      await _search();
    }
  }

  Future<String?> _askExtraPassword(rust_steam.SteamLobbyInfo room) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierColor: astralDialogBarrierColor,
      builder: (dialogContext) => AlertDialog(
        title: const Text('输入房间密码'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: '额外密码'),
            onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('加入'),
          ),
        ],
      ),
    ).then((value) => (value == null || value.isEmpty) ? null : value);
  }

  Future<bool?> _confirmOpen(rust_steam.SteamLobbyInfo room) {
    return showDialog<bool>(
      context: context,
      barrierColor: astralDialogBarrierColor,
      builder: (dialogContext) => AlertDialog(
        title: const Text('加入完全公开的房间？'),
        content: Text(
          '「${room.name}」没有设置额外密码，任何人搜到都能进来。'
          '如果不是你认识的房主，建议先确认再进。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }

  Widget _gateChip(BuildContext context, String gate) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (gate) {
      kSteamLobbyGateDouble => ('额外密码', Icons.key, scheme.primary),
      kSteamLobbyGateOpen => ('公开', Icons.public, scheme.error),
      _ => ('基础口令', Icons.lock_outline, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
        child: Column(
          children: [
            Icon(
              Icons.wifi_off,
              size: 32,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _search,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_rooms.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              Icons.search_off,
              size: 32,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('暂时没有同游戏的房间'),
            const SizedBox(height: 4),
            Text(
              '让好友先建房，或确认双方选的是同一个游戏。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _rooms.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final room = _rooms[index];
        final busy = _joiningLobbyId == room.lobbyId;
        final full = room.capacity > 0 && room.players >= room.capacity;
        return ListTile(
          enabled: !full && _joiningLobbyId == null,
          title: Row(
            children: [
              Flexible(
                child: Text(
                  room.name.isEmpty ? '未命名房间' : room.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _gateChip(context, room.gate),
            ],
          ),
          subtitle: Text(
            '房主 ${room.hostSteamId} · ${room.players}/${room.capacity} 人',
          ),
          trailing: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(full ? '已满' : '加入'),
          onTap: full ? null : () => _join(room),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('搜索房间'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<GameInfo>(
                    initialValue: _game,
                    decoration: const InputDecoration(
                      labelText: '游戏',
                      isDense: true,
                    ),
                    items: [
                      for (final game in widget.catalog)
                        DropdownMenuItem(
                          value: game,
                          child: Text(game.displayName),
                        ),
                    ],
                    onChanged: _joiningLobbyId != null
                        ? null
                        : (game) {
                            if (game == null || game.id == _game.id) return;
                            setState(() => _game = game);
                            _search();
                          },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading ? null : _search,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.space12),
            Expanded(child: _body()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
