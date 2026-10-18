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

/// 未被连接占用的探测目标。
///
/// 刷新时列表里每一台都要检测，所以不区分启用状态；只排除正在使用的服务器。
List<ServerMod> serversEligibleForPing(
  List<ServerMod> servers, {
  Set<int> activeIds = const {},
}) {
  return [
    for (final s in servers)
      if (!activeIds.contains(s.id)) s,
  ];
}

class ServerStatusState {
  final serverStatuses = signal<Map<int, ServerStatus>>({});
  final serverLatencies = signal<Map<int, int?>>({});

  /// 「加入节点」探测结果（是否 ET 服务器），仅在手动检测后写入。
  final serverProbes = signal<Map<int, ServerProbeResult>>({});

  /// 正在探测中的服务器 id，用于 UI 展示「探测中」。
  final probingServerIds = signal<Set<int>>({});

  /// 最近一次手动探测完成的时间，用于页头展示。
  final lastProbeAt = signal<DateTime?>(null);

  final activeServerIds = signal<Set<int>>({});
  final ServerProbeService _probeService = ServerProbeService();

  /// 记录探测时使用的地址，地址被修改后据此丢弃过期结果。
  final Map<int, String> _probedUrls = {};

  bool isProbing(int serverId) => probingServerIds.value.contains(serverId);

  ServerProbeResult? probeResultOf(int serverId) =>
      serverProbes.value[serverId];

  /// 手动触发一次「加入节点」探测（真实 ET 握手），每个服务器只探测一次。
  ///
  /// 只有用户点击刷新/下拉刷新时才会调用，不做任何自动轮询。
  /// 探测期间对应服务器进入「探测中」；完成后写入「是否 ET」，
  /// 并以 TCP ping 刷新 [serverLatencies] 与 [serverStatuses]。
  Future<void> probeServers(List<ServerMod> servers) async {
    if (servers.isEmpty) return;
    final activeIds = activeServerIds.value;
    // ET 握手探测覆盖整个列表（使用中的服务器除外），不区分启用状态：
    // 点刷新就是想知道列表里每一台是不是 EasyTier 服务器。
    final probeTargets = [
      for (final s in servers)
        if (!activeIds.contains(s.id)) s,
    ];
    // 延迟与在线状态同样覆盖所有未占用的服务器，不区分启用状态。
    final pingTargets = serversEligibleForPing(servers, activeIds: activeIds);
    if (probeTargets.isEmpty) return;
    final pendingIds = {for (final s in probeTargets) s.id};
    final pingIds = {for (final s in pingTargets) s.id};
    probingServerIds.value = {...probingServerIds.value, ...pendingIds};
    try {
      final probesFuture = Future.wait([
        for (final s in probeTargets) _probeService.probe(s),
      ]);
      final latenciesFuture = PingUtil.tcpPingMany([
        for (final s in pingTargets) s.url,
      ]);
      final results = await probesFuture;
      final rtts = await latenciesFuture;
      final nextProbes = Map<int, ServerProbeResult>.from(serverProbes.value);
      final nextLatencies = Map<int, int?>.from(serverLatencies.value);
      final nextStatuses = Map<int, ServerStatus>.from(serverStatuses.value);
      // 使用中的服务器不参与延迟测试，清掉上一次的延迟与在线状态。
      for (final server in servers) {
        if (pingIds.contains(server.id)) continue;
        nextLatencies.remove(server.id);
        nextStatuses[server.id] = activeIds.contains(server.id)
            ? ServerStatus.inUse
            : ServerStatus.unknown;
      }
      for (var i = 0; i < probeTargets.length; i++) {
        final server = probeTargets[i];
        nextProbes[server.id] = results[i];
        _probedUrls[server.id] = server.url;
      }
      for (var i = 0; i < pingTargets.length; i++) {
        final server = pingTargets[i];
        final latency = i < rtts.length ? rtts[i] : null;
        nextLatencies[server.id] = latency;
        nextStatuses[server.id] = latency != null
            ? ServerStatus.online
            : ServerStatus.offline;
      }
      serverProbes.value = nextProbes;
      serverLatencies.value = nextLatencies;
      serverStatuses.value = nextStatuses;
      lastProbeAt.value = DateTime.now();
    } finally {
      final remaining = {...probingServerIds.value}..removeAll(pendingIds);
      probingServerIds.value = remaining;
    }
  }

  /// 地址被修改或服务器被删除时，丢弃对应的旧探测结果。
  ///
  /// 启用/停用不影响检测结果：停用的服务器同样保留延迟与在线状态。
  void invalidateStaleProbes(List<ServerMod> servers) {
    final currentUrls = {for (final s in servers) s.id: s.url};
    final staleIds = <int>[];
    for (final entry in _probedUrls.entries) {
      if (currentUrls[entry.key] != entry.value) staleIds.add(entry.key);
    }
    if (staleIds.isEmpty) return;
    for (final id in staleIds) {
      _probedUrls.remove(id);
    }
    serverProbes.value = {
      for (final entry in serverProbes.value.entries)
        if (!staleIds.contains(entry.key)) entry.key: entry.value,
    };
    serverLatencies.value = {
      for (final entry in serverLatencies.value.entries)
        if (!staleIds.contains(entry.key)) entry.key: entry.value,
    };
    serverStatuses.value = {
      for (final entry in serverStatuses.value.entries)
        if (!staleIds.contains(entry.key)) entry.key: entry.value,
    };
  }

  void setActiveServers(Set<int> serverIds) {
    activeServerIds.value = serverIds;
  }

  ServerStatus getServerStatus(int serverId) {
    return serverStatuses.value[serverId] ?? ServerStatus.unknown;
  }
}
