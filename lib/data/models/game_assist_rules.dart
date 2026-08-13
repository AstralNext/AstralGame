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
///
/// JSON：对象 = 一条；数组 = 多条。有块即启用。
class GameAssistLanGameDiscoverConfig {
  const GameAssistLanGameDiscoverConfig({this.entries = const []});

  static const intervalMs = 4000;
  static const ttlMs = 18000;

  final List<GameAssistLanGameDiscoverEntry> entries;

  static GameAssistLanGameDiscoverConfig? tryParse(Object? raw) {
    final maps = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) maps.add(Map<String, dynamic>.from(e));
      }
    } else if (raw is Map) {
      maps.add(Map<String, dynamic>.from(raw));
    } else {
      return null;
    }
    final entries = [
      for (final m in maps) GameAssistLanGameDiscoverEntry.fromJson(m),
    ].where((e) => e.type.isNotEmpty).toList();
    if (entries.isEmpty) return null;
    return GameAssistLanGameDiscoverConfig(entries: entries);
  }
}

class GameAssistLanGameDiscoverEntry {
  const GameAssistLanGameDiscoverEntry({
    required this.id,
    required this.label,
    required this.type,
    this.port = 0,
    this.multicast,
    this.multicastPort = 0,
    this.parser,
    this.probe,
    this.title,
  });

  final String id;
  final String label;
  /// `static_port` | `udp_multicast` | `udp_probe`
  final String type;
  final int port;
  /// 组播地址（不含端口）。
  final String? multicast;
  final int multicastPort;
  /// `minecraft_motd` / `mindustry_server` …
  final String? parser;
  /// `udp_probe` 探测包十六进制，如 `fe01`。
  final String? probe;
  /// 标题模板：`{player}` `{game}` `{label}` `{motd}`。
  final String? title;

  Uint8List? get probeBytes {
    final raw = (probe ?? '').trim();
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
    final type = '${json['type'] ?? ''}'.trim().toLowerCase();
    final id = '${json['id'] ?? type}'.trim();
    final mcast = parseHostPort(_optionalString(json['multicast']));
    return GameAssistLanGameDiscoverEntry(
      id: id.isEmpty ? 'lan' : id,
      label: '${json['label'] ?? ''}'.trim(),
      type: type,
      port: (json['port'] as num?)?.toInt() ?? 0,
      multicast: mcast?.host,
      multicastPort: mcast?.port ?? 0,
      parser: _optionalString(json['parser']),
      probe: _optionalString(json['probe']),
      title: _optionalString(json['title']),
    );
  }
}

/// `224.0.2.60:4445` → host + port。
({String host, int port})? parseHostPort(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final i = s.lastIndexOf(':');
  if (i <= 0 || i == s.length - 1) return (host: s, port: 0);
  final port = int.tryParse(s.substring(i + 1).trim());
  if (port == null || port <= 0 || port > 65535) {
    return (host: s, port: 0);
  }
  return (host: s.substring(0, i).trim(), port: port);
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
      lanGameDiscover: GameAssistLanGameDiscoverConfig.tryParse(discover),
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
