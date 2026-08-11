import 'dart:typed_data';

/// 本地游戏规则目录（UI 元数据 / 网络标志 / 魔法墙 / TCP 转发 / 局域网发现）。
/// 数据源：`https://astral.fan/gamerules.json`（失败回退本地 asset）。
class GameAssistRulesCatalog {
  const GameAssistRulesCatalog({
    required this.version,
    required this.games,
  });

  final int version;
  /// 有序列表（按 JSON 中 `sort`）。
  final List<GameAssistGameRules> games;

  factory GameAssistRulesCatalog.fromJson(Map<String, dynamic> json) {
    final list = <GameAssistGameRules>[];
    final rawGames = json['games'];
    if (rawGames is List) {
      for (final e in rawGames) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final id = '${m['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        list.add(GameAssistGameRules.fromJson(id, m));
      }
    }
    list.sort((a, b) => a.sort.compareTo(b.sort));
    return GameAssistRulesCatalog(
      version: (json['version'] as num?)?.toInt() ?? 1,
      games: list,
    );
  }

  GameAssistGameRules? byId(String gameId) {
    for (final g in games) {
      if (g.id == gameId) return g;
    }
    return null;
  }

  /// 取当前平台配置；无该平台则返回 null。
  GameAssistPlatformRules? platformRules(String gameId, String platform) {
    return byId(gameId)?.platforms[platform];
  }

  Map<String, GameAssistGameRules> get gamesById => {
        for (final g in games) g.id: g,
      };
}

class GameAssistGameRules {
  const GameAssistGameRules({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.iconName,
    required this.platforms,
    this.steamAppId,
    this.sgdbGameId,
    this.iconAsset,
    this.gridAsset,
    this.showInPicker = true,
    this.sort = 100,
  });

  final String id;
  final String name;
  /// `#RRGGBB` 或 `#AARRGGBB`。
  final String colorHex;
  /// Material Icons 名称，如 `terrain`。
  final String iconName;
  final int? steamAppId;
  final int? sgdbGameId;
  final String? iconAsset;
  final String? gridAsset;
  final bool showInPicker;
  final int sort;
  final Map<String, GameAssistPlatformRules> platforms;

  /// 优先 [platform]，否则 `windows`，再否则任意有配置的平台。
  GameAssistPlatformRules? platformOrFallback(String platform) {
    return platforms[platform] ??
        platforms['windows'] ??
        (platforms.isEmpty ? null : platforms.values.first);
  }

  GameAssistLanGameDiscoverConfig? lanGameDiscoverFor(String platform) {
    return platformOrFallback(platform)?.lanGameDiscover;
  }

  GameAssistNetworkConfig networkFor(String platform) {
    return platformOrFallback(platform)?.network ??
        const GameAssistNetworkConfig();
  }

  factory GameAssistGameRules.fromJson(String id, Map<String, dynamic> json) {
    final raw = json['platforms'];
    final platforms = <String, GameAssistPlatformRules>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map) {
          platforms['$key'] = GameAssistPlatformRules.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    return GameAssistGameRules(
      id: id,
      name: '${json['name'] ?? id}'.trim().isEmpty
          ? id
          : '${json['name'] ?? id}'.trim(),
      colorHex: '${json['color'] ?? '#6B7280'}'.trim(),
      iconName: '${json['icon'] ?? 'sports_esports_outlined'}'.trim(),
      steamAppId: (json['steam_app_id'] as num?)?.toInt(),
      sgdbGameId: (json['sgdb_game_id'] as num?)?.toInt(),
      iconAsset: _optionalString(json['icon_asset']),
      gridAsset: _optionalString(json['grid_asset']),
      showInPicker: json['show_in_picker'] != false,
      sort: (json['sort'] as num?)?.toInt() ?? 100,
      platforms: platforms,
    );
  }
}

/// 发现本机开放游戏，并经 EasyTier 隧道向房间同伴宣告。
class GameAssistLanGameDiscoverConfig {
  const GameAssistLanGameDiscoverConfig({
    required this.enabled,
    this.hostOnly = false,
    this.intervalMs = 5000,
    this.ttlMs = 18000,
    this.entries = const [],
  });

  final bool enabled;
  /// 仅房主宣告自己的开放服。
  final bool hostOnly;
  final int intervalMs;
  final int ttlMs;
  final List<GameAssistLanGameDiscoverEntry> entries;

  factory GameAssistLanGameDiscoverConfig.fromJson(Map<String, dynamic> json) {
    return GameAssistLanGameDiscoverConfig(
      enabled: json['enabled'] == true,
      hostOnly: json['host_only'] == true,
      intervalMs: (json['interval_ms'] as num?)?.toInt() ?? 5000,
      ttlMs: (json['ttl_ms'] as num?)?.toInt() ?? 18000,
      entries: [
        if (json['entries'] is List)
          for (final e in json['entries'] as List)
            if (e is Map)
              GameAssistLanGameDiscoverEntry.fromJson(
                Map<String, dynamic>.from(e),
              ),
      ],
    );
  }
}

class GameAssistLanGameDiscoverEntry {
  const GameAssistLanGameDiscoverEntry({
    required this.id,
    required this.label,
    required this.type,
    this.port = 0,
    this.multicast,
    this.multicastPort,
    this.parser,
    this.probeHex,
    this.params = const {},
  });

  final String id;
  final String label;
  /// 发现器类型：`static_port` | `udp_multicast` | `udp_probe`。
  final String type;
  /// `static_port` 端口；`udp_probe` 的游戏端口 / parser 回退端口。
  final int port;
  /// `udp_multicast` / `udp_probe`：组播组 / 端口。
  final String? multicast;
  final int? multicastPort;
  /// 载荷解析器名：`minecraft_motd`（内核）/ `mindustry_server`（Dart）等。
  final String? parser;
  /// `udp_probe`：探测包十六进制（如 Mindustry DiscoverHost `fe01`）。
  final String? probeHex;
  /// 预留扩展字段（超时、是否广播等）。
  final Map<String, dynamic> params;

  /// 解析 [probeHex]；非法则 null。
  Uint8List? get probeBytes {
    final raw = (probeHex ?? '').trim();
    if (raw.isEmpty) return null;
    final hex = raw.replaceAll(RegExp(r'[\s:_-]'), '');
    if (hex.length.isOdd) return null;
    try {
      final out = Uint8List(hex.length ~/ 2);
      for (var i = 0; i < out.length; i++) {
        out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  factory GameAssistLanGameDiscoverEntry.fromJson(Map<String, dynamic> json) {
    final id = '${json['id'] ?? 'default'}'.trim();
    final type =
        '${json['type'] ?? 'static_port'}'.trim().toLowerCase();
    final paramsRaw = json['params'];
    final params = <String, dynamic>{};
    if (paramsRaw is Map) {
      params.addAll(Map<String, dynamic>.from(paramsRaw));
    }
    // 也允许把 probe 写在 params 里
    final probe = _optionalString(json['probe_hex']) ??
        _optionalString(params['probe_hex']);
    return GameAssistLanGameDiscoverEntry(
      id: id.isEmpty ? 'default' : id,
      label: '${json['label'] ?? '开放游戏'}'.trim().isEmpty
          ? '开放游戏'
          : '${json['label'] ?? '开放游戏'}'.trim(),
      type: type,
      port: (json['port'] as num?)?.toInt() ?? 0,
      multicast: _optionalString(json['multicast']),
      multicastPort: (json['multicast_port'] as num?)?.toInt(),
      parser: _optionalString(json['parser']),
      probeHex: probe,
      params: params,
    );
  }
}

/// 去掉 CIDR，得到纯 IPv4；无效则 null。
String? stripIpv4Host(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  final slash = s.indexOf('/');
  if (slash >= 0) s = s.substring(0, slash).trim();
  if (s.isEmpty || s == '0.0.0.0') return null;
  return s;
}

/// EasyTier / 虚拟网相关开关（按平台）。
class GameAssistNetworkConfig {
  const GameAssistNetworkConfig({
    this.enableUdpBroadcastRelay = false,
  });

  /// 写入 TOML `[flags] enable_udp_broadcast_relay`（Windows）。
  final bool enableUdpBroadcastRelay;

  factory GameAssistNetworkConfig.fromJson(Map<String, dynamic> json) {
    return GameAssistNetworkConfig(
      enableUdpBroadcastRelay: json['enable_udp_broadcast_relay'] == true,
    );
  }
}

class GameAssistPlatformRules {
  const GameAssistPlatformRules({
    this.network = const GameAssistNetworkConfig(),
    required this.magicWall,
    required this.forwards,
    this.lanGameDiscover,
  });

  final GameAssistNetworkConfig network;
  final GameAssistMagicWallConfig magicWall;
  final List<GameAssistForwardRule> forwards;
  /// 发现本机开放游戏并经 ET 宣告。
  final GameAssistLanGameDiscoverConfig? lanGameDiscover;

  factory GameAssistPlatformRules.fromJson(Map<String, dynamic> json) {
    final mw = json['magic_wall'];
    final discover = json['lan_game_discover'];
    final net = json['network'];
    return GameAssistPlatformRules(
      network: net is Map
          ? GameAssistNetworkConfig.fromJson(Map<String, dynamic>.from(net))
          : const GameAssistNetworkConfig(),
      magicWall: mw is Map
          ? GameAssistMagicWallConfig.fromJson(Map<String, dynamic>.from(mw))
          : const GameAssistMagicWallConfig(enabled: false, rules: []),
      forwards: [
        if (json['forwards'] is List)
          for (final e in json['forwards'] as List)
            if (e is Map)
              GameAssistForwardRule.fromJson(Map<String, dynamic>.from(e)),
      ],
      lanGameDiscover: discover is Map
          ? GameAssistLanGameDiscoverConfig.fromJson(
              Map<String, dynamic>.from(discover),
            )
          : null,
    );
  }
}

class GameAssistMagicWallConfig {
  const GameAssistMagicWallConfig({
    required this.enabled,
    required this.rules,
  });

  final bool enabled;
  final List<GameAssistMagicWallRule> rules;

  factory GameAssistMagicWallConfig.fromJson(Map<String, dynamic> json) {
    return GameAssistMagicWallConfig(
      enabled: json['enabled'] == true,
      rules: [
        if (json['rules'] is List)
          for (final e in json['rules'] as List)
            if (e is Map)
              GameAssistMagicWallRule.fromJson(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

class GameAssistMagicWallRule {
  const GameAssistMagicWallRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.action,
    required this.protocol,
    required this.direction,
    this.appPath,
    this.remoteIp,
    this.localIp,
    this.remotePort,
    this.localPort,
    this.description,
  });

  final String id;
  final String name;
  final bool enabled;
  final String action;
  final String protocol;
  final String direction;
  final String? appPath;
  final String? remoteIp;
  final String? localIp;
  final String? remotePort;
  final String? localPort;
  final String? description;

  factory GameAssistMagicWallRule.fromJson(Map<String, dynamic> json) {
    return GameAssistMagicWallRule(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? 'rule'}',
      enabled: json['enabled'] != false,
      action: '${json['action'] ?? 'allow'}',
      protocol: '${json['protocol'] ?? 'both'}',
      direction: '${json['direction'] ?? 'inbound'}',
      appPath: json['app_path']?.toString(),
      remoteIp: json['remote_ip']?.toString(),
      localIp: json['local_ip']?.toString(),
      remotePort: json['remote_port']?.toString(),
      localPort: json['local_port']?.toString(),
      description: json['description']?.toString(),
    );
  }
}

class GameAssistForwardRule {
  const GameAssistForwardRule({
    required this.listen,
    required this.target,
    this.proto = 'tcp',
    this.hostOnly = true,
  });

  final String listen;
  final String target;
  final String proto;
  /// 仅房主启动该转发。
  final bool hostOnly;

  factory GameAssistForwardRule.fromJson(Map<String, dynamic> json) {
    return GameAssistForwardRule(
      listen: '${json['listen'] ?? ''}'.trim(),
      target: '${json['target'] ?? ''}'.trim(),
      proto: '${json['proto'] ?? 'tcp'}'.trim().toLowerCase(),
      hostOnly: json['host_only'] != false,
    );
  }
}

String? _optionalString(Object? v) {
  final s = v?.toString().trim();
  if (s == null || s.isEmpty) return null;
  return s;
}
