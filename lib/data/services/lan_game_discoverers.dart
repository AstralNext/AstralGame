import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/open_game_listing.dart';
import 'package:astral_game/data/services/lan_inject_guard.dart';
import 'package:astral_game/data/services/lan_payload_parsers.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_rust_core/astral_rust_core.dart';

/// 某条发现规则在本机扫到的候选（尚未绑定虚拟 IP）。
class DiscoveredGameHit {
  const DiscoveredGameHit({
    required this.port,
    required this.label,
    this.motd,
    this.parser,
  });

  final int port;
  final String label;
  final String? motd;
  final String? parser;
}

/// 可插拔局域网发现器：新游戏加配置（必要时加 parser），不必改 OpenGames 主干。
abstract class LanGameDiscoverer {
  String get type;

  /// 进房时启动（监听/探测）。默认可空。
  Future<void> start(GameAssistLanGameDiscoverEntry entry) async {}

  /// 退房时停止。默认可空。
  Future<void> stop() async {}

  /// 拉取当前命中；[virtualIp] 由上层拼进宣告。
  Future<List<DiscoveredGameHit>> poll(GameAssistLanGameDiscoverEntry entry);
}

/// `static_port`：规则写死端口（泰拉 / 星露谷等无 LAN 扫描时用）。
/// 仅当本机该 UDP 端口已被占用时才宣告。
class StaticPortDiscoverer extends LanGameDiscoverer {
  @override
  String get type => 'static_port';

  @override
  Future<List<DiscoveredGameHit>> poll(GameAssistLanGameDiscoverEntry entry) async {
    if (entry.port <= 0) return const [];
    if (!await _isUdpPortInUse(entry.port)) return const [];
    return [
      DiscoveredGameHit(
        port: entry.port,
        label: entry.label.trim().isEmpty ? '开放游戏' : entry.label,
      ),
    ];
  }

  /// 尝试绑定端口：能绑上说明当前无人占用；绑失败则视为游戏等进程在听。
  Future<bool> _isUdpPortInUse(int port) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
      );
      socket.close();
      return false;
    } catch (_) {
      return true;
    }
  }
}

/// `udp_multicast`：听组播，按 [parser] 解析载荷（如 MC MOTD，内核侧）。
class UdpMulticastDiscoverer extends LanGameDiscoverer {
  @override
  String get type => 'udp_multicast';

  final Set<String> _startedKeys = {};
  final Map<int, _CachedHit> _lastReal = {};

  @override
  Future<void> start(GameAssistLanGameDiscoverEntry entry) async {
    final group = (entry.multicast ?? '').trim();
    final port = entry.multicastPort;
    final parser = (entry.parser ?? '').trim();
    if (group.isEmpty || port <= 0 || parser.isEmpty) {
      appLogger.w(
        '[LanDiscover] udp_multicast 配置不完整 '
        'group=$group port=$port parser=$parser',
      );
      return;
    }
    final key = '$group:$port:$parser';
    if (!_startedKeys.add(key)) return;
    try {
      await startUdpMulticastLanListener(
        multicastAddr: group,
        port: port,
        parser: parser,
      );
      appLogger.i('[LanDiscover] udp_multicast 已听 $key');
    } catch (e) {
      _startedKeys.remove(key);
      appLogger.w('[LanDiscover] udp_multicast 启动失败 $key: $e');
    }
  }

  @override
  Future<void> stop() async {
    _startedKeys.clear();
    _lastReal.clear();
  }

  @override
  Future<List<DiscoveredGameHit>> poll(GameAssistLanGameDiscoverEntry entry) async {
    final parser = (entry.parser ?? '').trim();
    if (parser.isEmpty) return const [];
    try {
      final all = await pollLanGameDiscoveries();
      final now = DateTime.now();
      final out = <DiscoveredGameHit>[];
      for (final d in all) {
        if (d.parser != parser) continue;
        if (LanInjectGuard.shouldIgnoreDiscovery(
          motd: d.motd,
          sourceIp: d.sourceIp,
          gamePort: d.gamePort,
        )) {
          final prev = _lastReal[d.gamePort];
          if (prev != null &&
              now.difference(prev.at) < const Duration(seconds: 18)) {
            out.add(prev.hit);
          }
          continue;
        }
        final hit = DiscoveredGameHit(
          port: d.gamePort,
          label: d.motd.trim().isNotEmpty ? d.motd.trim() : entry.label,
          motd: d.motd.trim().isEmpty ? null : d.motd.trim(),
          parser: d.parser,
        );
        _lastReal[d.gamePort] = _CachedHit(hit, now);
        out.add(hit);
      }
      _lastReal.removeWhere(
        (_, v) => now.difference(v.at) > const Duration(seconds: 18),
      );
      return out;
    } catch (e) {
      appLogger.d('[LanDiscover] poll 失败: $e');
      return const [];
    }
  }
}

/// `udp_probe`：发探测包，再用 [parser] 解析回复（如 Mindustry DiscoverHost）。
class UdpProbeDiscoverer extends LanGameDiscoverer {
  @override
  String get type => 'udp_probe';

  final Map<String, _CachedHit> _cache = {};

  @override
  Future<void> stop() async {
    _cache.clear();
  }

  @override
  Future<List<DiscoveredGameHit>> poll(GameAssistLanGameDiscoverEntry entry) async {
    final parserName = (entry.parser ?? '').trim();
    final parser = lanPayloadParserOf(parserName);
    final probe = entry.probeBytes;
    if (parser == null || probe == null || probe.isEmpty) {
      appLogger.w(
        '[LanDiscover] udp_probe 配置不完整 id=${entry.id} '
        'parser=$parserName probe=${entry.probe}',
      );
      return const [];
    }

    final multicast = (entry.multicast ?? '').trim();
    final multicastPort = entry.multicastPort;
    final gamePort = entry.port;

    try {
      final hits = await _probeOnce(
        probe: probe,
        parser: parser,
        parserName: parserName,
        fallbackLabel:
            entry.label.trim().isEmpty ? entry.type : entry.label,
        fallbackPort: gamePort > 0 ? gamePort : 0,
        multicast: multicast,
        multicastPort: multicastPort,
        gamePort: gamePort,
      );
      final now = DateTime.now();
      final cacheKeyPrefix = '${entry.id}:';
      for (final h in hits) {
        _cache['$cacheKeyPrefix${h.port}'] = _CachedHit(h, now);
      }
      _cache.removeWhere(
        (k, v) =>
            k.startsWith(cacheKeyPrefix) &&
            now.difference(v.at) > const Duration(seconds: 18),
      );
    } catch (e) {
      appLogger.d('[LanDiscover] udp_probe 失败 id=${entry.id}: $e');
    }

    return [
      for (final e in _cache.entries)
        if (e.key.startsWith('${entry.id}:')) e.value.hit,
    ];
  }

  Future<List<DiscoveredGameHit>> _probeOnce({
    required Uint8List probe,
    required LanPayloadParser parser,
    required String parserName,
    required String fallbackLabel,
    required int fallbackPort,
    required String multicast,
    required int multicastPort,
    required int gamePort,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    socket.readEventsEnabled = true;

    final found = <int, DiscoveredGameHit>{};
    final locals = await _localIpv4Set();

    void consider(Datagram? dg) {
      if (dg == null || dg.data.isEmpty) return;
      if (dg.address.type != InternetAddressType.IPv4) return;
      final ip = dg.address.address;
      if (!_isOwnIpv4(ip, locals)) return;
      final parsed = parser(dg.data, fallbackPort: fallbackPort);
      if (parsed == null || parsed.port <= 0) return;
      found[parsed.port] = DiscoveredGameHit(
        port: parsed.port,
        label: parsed.label.isNotEmpty ? parsed.label : fallbackLabel,
        motd: parsed.motd,
        parser: parserName,
      );
    }

    void drain() {
      while (true) {
        final dg = socket.receive();
        if (dg == null) break;
        consider(dg);
      }
    }

    final sub = socket.listen((event) {
      if (event == RawSocketEvent.read) drain();
    });

    try {
      if (multicast.isNotEmpty && multicastPort > 0) {
        try {
          socket.send(probe, InternetAddress(multicast), multicastPort);
        } catch (_) {}
      }
      if (gamePort > 0) {
        try {
          socket.send(probe, InternetAddress.loopbackIPv4, gamePort);
        } catch (_) {}
        try {
          socket.send(probe, InternetAddress('255.255.255.255'), gamePort);
        } catch (_) {}
        for (final ip in locals) {
          if (ip == '127.0.0.1') continue;
          final parts = ip.split('.');
          if (parts.length != 4) continue;
          try {
            socket.send(
              probe,
              InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'),
              gamePort,
            );
          } catch (_) {}
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 700));
      drain();
    } finally {
      await sub.cancel();
      socket.close();
    }

    return found.values.toList(growable: false);
  }

  Future<Set<String>> _localIpv4Set() async {
    final set = <String>{'127.0.0.1'};
    try {
      for (final iface in await NetworkInterface.list()) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            set.add(addr.address);
          }
        }
      }
    } catch (_) {}
    return set;
  }

  bool _isOwnIpv4(String ip, Set<String> locals) {
    return locals.contains(ip) || ip.startsWith('127.');
  }
}

class _CachedHit {
  _CachedHit(this.hit, this.at);
  final DiscoveredGameHit hit;
  final DateTime at;
}

/// 发现器注册表。扩展：实现 [LanGameDiscoverer] 后 `register`。
class LanGameDiscovererRegistry {
  LanGameDiscovererRegistry._() {
    register(StaticPortDiscoverer());
    register(UdpMulticastDiscoverer());
    register(UdpProbeDiscoverer());
  }

  static final LanGameDiscovererRegistry instance = LanGameDiscovererRegistry._();

  final Map<String, LanGameDiscoverer> _byType = {};

  void register(LanGameDiscoverer discoverer) {
    _byType[discoverer.type] = discoverer;
  }

  LanGameDiscoverer? of(String type) => _byType[type];

  Future<List<LocalOpenGameAd>> collectAds({
    required List<GameAssistLanGameDiscoverEntry> entries,
    required String roomGameId,
    required String virtualIp,
  }) async {
    final out = <LocalOpenGameAd>[];
    for (final e in entries) {
      final d = of(e.type);
      if (d == null) {
        appLogger.w('[LanDiscover] 未知 type=${e.type} id=${e.id}');
        continue;
      }
      final hits = await d.poll(e);
      for (final hit in hits) {
        if (hit.port <= 0) continue;
        out.add(
          LocalOpenGameAd(
            entry: e,
            ipv4: virtualIp,
            roomGameId: roomGameId,
            port: hit.port,
            label: hit.label,
            motd: hit.motd,
          ),
        );
      }
    }
    return out;
  }

  Future<void> startAll(List<GameAssistLanGameDiscoverEntry> entries) async {
    for (final e in entries) {
      final d = of(e.type);
      if (d == null) continue;
      await d.start(e);
    }
  }

  Future<void> stopAll() async {
    for (final d in _byType.values) {
      await d.stop();
    }
    try {
      await stopAllLanGameListeners();
    } catch (_) {}
  }
}
