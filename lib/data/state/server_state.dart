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

class ServerStatusState {
  final serverStatuses = signal<Map<int, ServerStatus>>({});
  final serverLatencies = signal<Map<int, int?>>({});
  final activeServerIds = signal<Set<int>>({});
  Timer? _checkTimer;

  void startPeriodicCheck(List<ServerMod> servers, Duration interval) {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(interval, (_) {
      checkServersStatus(servers);
    });
    checkServersStatus(servers);
  }

  void stopPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  Future<void> checkServersStatus(List<ServerMod> servers) async {
    final activeIds = activeServerIds.value;
    final Map<int, ServerStatus> newStatuses = {};
    final Map<int, int?> newLatencies = {};

    // 并行 ping 所有服务器
    final futures = servers.map((server) async {
      if (activeIds.contains(server.id)) {
        newStatuses[server.id] = ServerStatus.inUse;
        newLatencies[server.id] = null;
        return;
      }

      final latency = await _checkServerLatency(server);
      newLatencies[server.id] = latency;
      newStatuses[server.id] =
          latency != null ? ServerStatus.online : ServerStatus.offline;
    });

    await Future.wait(futures);
    serverStatuses.value = newStatuses;
    serverLatencies.value = newLatencies;
  }

  Future<int?> _checkServerLatency(ServerMod server) async {
    try {
      return await PingUtil.ping(server.url);
    } catch (e) {
      return null;
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


