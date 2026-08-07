import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/open_game_listing.dart';
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

/// 可插拔局域网发现器：新游戏加实现 + 注册即可，不必改 OpenGames 主干。
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

/// `udp_multicast`：听组播，按 [parser] 解析载荷（如 MC MOTD）。
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
    // 由 OpenGamesService 统一 stopAllLanGameListeners。
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

/// 发现器注册表。扩展：实现 [LanGameDiscoverer] 后 `register`。
class LanGameDiscovererRegistry {
  LanGameDiscovererRegistry._() {
    register(StaticPortDiscoverer());
    register(UdpMulticastDiscoverer());
  }

  static final LanGameDiscovererRegistry instance = LanGameDiscovererRegistry._();

  final Map<String, LanGameDiscoverer> _byType = {};

  void register(LanGameDiscoverer discoverer) {
    _byType[discoverer.type] = discoverer;
  }

  LanGameDiscoverer? of(String type) => _byType[type];

  /// 把规则条目交给对应发现器，产出可宣告的本机广告。
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
