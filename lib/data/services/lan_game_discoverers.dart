import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/open_game_listing.dart';
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

/// `static_port`：规则里写死端口（泰拉等无标准 LAN 广播时用）。
class StaticPortDiscoverer extends LanGameDiscoverer {
  @override
  String get type => 'static_port';

  @override
  Future<List<DiscoveredGameHit>> poll(GameAssistLanGameDiscoverEntry entry) async {
    if (entry.port <= 0) return const [];
    return [
      DiscoveredGameHit(port: entry.port, label: entry.label),
    ];
  }
}

/// `udp_multicast`：听组播，按 [parser] 解析载荷（如 MC MOTD，内核侧）。
class UdpMulticastDiscoverer extends LanGameDiscoverer {
  @override
  String get type => 'udp_multicast';

  final Set<String> _startedKeys = {};

  @override
  Future<void> start(GameAssistLanGameDiscoverEntry entry) async {
    final group = (entry.multicast ?? '').trim();
    final port = entry.multicastPort ?? 0;
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
  }

  @override
  Future<List<DiscoveredGameHit>> poll(GameAssistLanGameDiscoverEntry entry) async {
    final parser = (entry.parser ?? '').trim();
    if (parser.isEmpty) return const [];
    try {
      final all = await pollLanGameDiscoveries();
      return [
        for (final d in all)
          if (d.parser == parser)
            DiscoveredGameHit(
              port: d.gamePort,
              label: d.motd.trim().isNotEmpty ? d.motd.trim() : entry.label,
              motd: d.motd.trim().isEmpty ? null : d.motd.trim(),
              parser: d.parser,
            ),
      ];
    } catch (e) {
      appLogger.d('[LanDiscover] poll 失败: $e');
      return const [];
    }
  }
}

/// `udp_probe`：按配置发探测包，再用 [parser] 解析回复（如 Mindustry DiscoverHost）。
///
/// 配置字段：
/// - `probe_hex`：探测载荷（如 `fe01`）
/// - `multicast` / `multicast_port`：组播探测（可选）
/// - `port`：游戏端口；用于回环/广播探测与 parser 回退端口
/// - `parser`：Dart 侧载荷解析器名（如 `mindustry_server`）
/// - `params.also_broadcast` / `also_loopback`（默认 true）
/// - `params.timeout_ms`（默认 700）
/// - `params.local_only`（默认 true，只认本机源地址）
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
        'parser=$parserName probe=${entry.probeHex}',
      );
      return const [];
    }

    final multicast = (entry.multicast ?? '').trim();
    final multicastPort = entry.multicastPort ?? 0;
    final gamePort = entry.port;
    final timeoutMs = _paramInt(entry, 'timeout_ms', 700);
    final localOnly = _paramBool(entry, 'local_only', true);
    final alsoBroadcast = _paramBool(entry, 'also_broadcast', true);
    final alsoLoopback = _paramBool(entry, 'also_loopback', true);

    try {
      final hits = await _probeOnce(
        probe: probe,
        parser: parser,
        parserName: parserName,
        fallbackLabel: entry.label,
        fallbackPort: gamePort > 0 ? gamePort : 0,
        multicast: multicast,
        multicastPort: multicastPort,
        gamePort: gamePort,
        timeoutMs: timeoutMs,
        localOnly: localOnly,
        alsoBroadcast: alsoBroadcast,
        alsoLoopback: alsoLoopback,
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
    required int timeoutMs,
    required bool localOnly,
    required bool alsoBroadcast,
    required bool alsoLoopback,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    socket.readEventsEnabled = true;

    final found = <int, DiscoveredGameHit>{};
    final locals = localOnly ? await _localIpv4Set() : const <String>{};

    void consider(Datagram? dg) {
      if (dg == null || dg.data.isEmpty) return;
      if (dg.address.type != InternetAddressType.IPv4) return;
      final ip = dg.address.address;
      if (localOnly && !_isOwnIpv4(ip, locals)) return;
      final parsed = parser(dg.data, fallbackPort: fallbackPort);
      if (parsed == null || parsed.port <= 0) return;
      found[parsed.port] = DiscoveredGameHit(
        port: parsed.port,
        label: parsed.label.isNotEmpty ? parsed.label : fallbackLabel,
        motd: parsed.motd,
        parser: parserName,
      );
    }

    try {
      if (multicast.isNotEmpty && multicastPort > 0) {
        try {
          socket.send(probe, InternetAddress(multicast), multicastPort);
        } catch (_) {}
      }
      if (gamePort > 0) {
        if (alsoLoopback) {
          try {
            socket.send(probe, InternetAddress.loopbackIPv4, gamePort);
          } catch (_) {}
        }
        if (alsoBroadcast) {
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
      }

      final until = DateTime.now().add(Duration(milliseconds: timeoutMs));
      while (DateTime.now().isBefore(until)) {
        consider(socket.receive());
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      for (var i = 0; i < 8; i++) {
        final dg = socket.receive();
        if (dg == null) break;
        consider(dg);
      }
    } finally {
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

  static int _paramInt(GameAssistLanGameDiscoverEntry e, String key, int def) {
    final v = e.params[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }

  static bool _paramBool(GameAssistLanGameDiscoverEntry e, String key, bool def) {
    final v = e.params[key];
    if (v is bool) return v;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return def;
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
