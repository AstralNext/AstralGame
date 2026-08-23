import 'dart:async';

import 'package:signals/signals.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/utils/ping_util.dart';

typedef ServerPersistenceCallback = Future<List<ServerMod>> Function();
typedef ServerSaveCallback = Future<void> Function(List<ServerMod>);

enum ServerStatus {
  online,
  offline,
  inUse,
  unknown,
}

class ServerState {
  final servers = signal<List<ServerMod>>([]);
  ServerPersistenceCallback? _loadCallback;
  ServerSaveCallback? _saveCallback;

  void setPersistenceCallbacks({
    required ServerPersistenceCallback loadCallback,
    required ServerSaveCallback saveCallback,
  }) {
    _loadCallback = loadCallback;
    _saveCallback = saveCallback;
  }

  Future<void> loadFromPersistence() async {
    if (_loadCallback != null) {
      final loaded = await _loadCallback!();
      servers.value = loaded;
    }
  }

  Future<void> _saveToPersistence() async {
    if (_saveCallback != null) {
      await _saveCallback!(servers.value);
    }
  }

  Future<void> setServers(List<ServerMod> serverList) async {
    servers.value = serverList;
    await _saveToPersistence();
  }

  Future<void> addServer(ServerMod server) async {
    final list = List<ServerMod>.from(servers.value);
    list.add(server);
    servers.value = list;
    await _saveToPersistence();
  }

  Future<void> removeServer(int id) async {
    final list = servers.value.where((s) => s.id != id).toList();
    servers.value = list;
    await _saveToPersistence();
  }

  Future<void> updateServer(ServerMod updatedServer) async {
    final list = servers.value.map((s) {
      return s.id == updatedServer.id ? updatedServer : s;
    }).toList();
    servers.value = list;
    await _saveToPersistence();
  }

  Future<void> reorderServers(List<ServerMod> reordered) async {
    servers.value = reordered;
    await _saveToPersistence();
  }

  Future<void> toggleServerEnabled(int id, bool enabled) async {
    final list = servers.value.map((s) {
      if (s.id == id) {
        return s.copyWith(enable: enabled);
      }
      return s;
    }).toList();
    servers.value = list;
    await _saveToPersistence();
  }

  ServerMod? getServerById(int id) {
    try {
      return servers.value.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }

  List<ServerMod> getEnabledServers() {
    return servers.value.where((s) => s.enable).toList();
  }
}

/// 未占用且已启用的探测目标（禁用节点不发 ICMP）。
List<ServerMod> serversEligibleForPing(
  List<ServerMod> servers, {
  Set<int> activeIds = const {},
}) {
  return [
    for (final s in servers)
      if (s.enable && !activeIds.contains(s.id)) s,
  ];
}

class ServerStatusState {
  final serverStatuses = signal<Map<int, ServerStatus>>({});
  final serverLatencies = signal<Map<int, int?>>({});
  final activeServerIds = signal<Set<int>>({});
  Timer? _checkTimer;
  bool _checking = false;

  void startPeriodicCheck(List<ServerMod> servers, Duration interval) {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(interval, (_) {
      unawaited(checkServersStatus(servers));
    });
    unawaited(checkServersStatus(servers));
  }

  void stopPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  Future<void> checkServersStatus(List<ServerMod> servers) async {
    if (_checking) return;
    _checking = true;
    try {
      final activeIds = activeServerIds.value;
      final Map<int, ServerStatus> newStatuses = {};
      final Map<int, int?> newLatencies = {};

      for (final server in servers) {
        if (activeIds.contains(server.id)) {
          newStatuses[server.id] = ServerStatus.inUse;
          newLatencies[server.id] = null;
        } else if (!server.enable) {
          newStatuses[server.id] = ServerStatus.unknown;
          newLatencies[server.id] = null;
        }
      }

      final targets = serversEligibleForPing(servers, activeIds: activeIds);
      List<int?> rtts = const [];
      try {
        rtts = await PingUtil.pingMany([for (final s in targets) s.url]);
      } catch (_) {
        rtts = List<int?>.filled(targets.length, null);
      }
      for (var i = 0; i < targets.length; i++) {
        final latency = i < rtts.length ? rtts[i] : null;
        newLatencies[targets[i].id] = latency;
        newStatuses[targets[i].id] =
            latency != null ? ServerStatus.online : ServerStatus.offline;
      }

      serverStatuses.value = newStatuses;
      serverLatencies.value = newLatencies;
    } finally {
      _checking = false;
    }
  }

  void setActiveServers(Set<int> serverIds) {
    activeServerIds.value = serverIds;
  }

  ServerStatus getServerStatus(int serverId) {
    return serverStatuses.value[serverId] ?? ServerStatus.unknown;
  }

  void dispose() {
    stopPeriodicCheck();
  }
}


