import 'package:astral_game/utils/logger.dart';
import 'dart:async';

import 'package:signals/signals.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/server_probe_service.dart';
import 'package:astral_game/utils/ping_util.dart';

typedef ServerPersistenceCallback = Future<List<ServerMod>> Function();
typedef ServerSaveCallback = Future<void> Function(List<ServerMod>);

enum ServerStatus { online, offline, inUse, unknown }

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

  /// 「加入节点」探测结果（是否 ET 服务器 + 版本），仅在手动检测后写入。
  final serverProbes = signal<Map<int, ServerProbeResult>>({});

  /// 正在探测中的服务器 id，用于 UI 展示「探测中」。
  final probingServerIds = signal<Set<int>>({});
  final activeServerIds = signal<Set<int>>({});
  final ServerProbeService _probeService = ServerProbeService();
  Timer? _checkTimer;
  bool _checking = false;

  bool isProbing(int serverId) => probingServerIds.value.contains(serverId);

  ServerProbeResult? probeResultOf(int serverId) =>
      serverProbes.value[serverId];

  /// 手动触发一次「加入节点」探测（模拟 ET 握手），每个服务器只探测一次。
  ///
  /// 探测期间对应服务器进入「探测中」；完成后写入「是否 ET + 版本」，并以
  /// TCP ping 刷新 [serverLatencies]（延迟不走模拟探测）。
  Future<void> probeServers(List<ServerMod> servers) async {
    if (servers.isEmpty) return;
    final pendingIds = {for (final s in servers) s.id};
    probingServerIds.value = {...probingServerIds.value, ...pendingIds};
    try {
      final probesFuture = Future.wait([
        for (final s in servers) _probeService.probe(s),
      ]);
      final latenciesFuture = PingUtil.tcpPingMany([
        for (final s in servers) s.url,
      ]);
      final results = await probesFuture;
      final rtts = await latenciesFuture;
      final nextProbes = Map<int, ServerProbeResult>.from(serverProbes.value);
      final nextLatencies = Map<int, int?>.from(serverLatencies.value);
      for (var i = 0; i < servers.length; i++) {
        nextProbes[servers[i].id] = results[i];
        nextLatencies[servers[i].id] = i < rtts.length ? rtts[i] : null;
      }
      serverProbes.value = nextProbes;
      serverLatencies.value = nextLatencies;
    } finally {
      final remaining = {...probingServerIds.value}..removeAll(pendingIds);
      probingServerIds.value = remaining;
    }
  }

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
        rtts = await PingUtil.tcpPingMany([for (final s in targets) s.url]);
      } catch (e) {
        appLogger.w('[ServerState] 操作失败', error: e);
        rtts = List<int?>.filled(targets.length, null);
      }
      for (var i = 0; i < targets.length; i++) {
        final latency = i < rtts.length ? rtts[i] : null;
        newLatencies[targets[i].id] = latency;
        newStatuses[targets[i].id] = latency != null
            ? ServerStatus.online
            : ServerStatus.offline;
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
