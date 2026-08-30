import 'package:astral_game/utils/logger.dart';
import 'dart:typed_data';

import 'package:astral_game/utils/net_addr.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'game_assist_rules.freezed.dart';

/// 本地游戏规则目录（UI 元数据 / 网络标志 / 魔法墙 / TCP 转发 / 局域网发现）。
///
/// 数据源：测试目录 `gamerules/` → 否则 `https://astral.fan/gamerules.json`（失败回退本地 asset）。
@freezed
abstract class GameAssistRulesCatalog with _$GameAssistRulesCatalog {
const GameAssistRulesCatalog._();

const factory GameAssistRulesCatalog({
required final int version,

/// 有序列表（按 JSON 中 `sort`）。
required final List<GameAssistGameRules> games,
}) = _GameAssistRulesCatalog;

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

@freezed
abstract class GameAssistGameRules with _$GameAssistGameRules {

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
description: _optionalString(json['description']) ?? '',
nameZh: _optionalString(json['name_zh']) ?? '',
platforms: platforms,
);
}
const GameAssistGameRules._();

const factory GameAssistGameRules({
required final String id,
required final String name,

/// `#RRGGBB` 或 `#AARRGGBB`。
required final String colorHex,

/// Material Icons 名称，如 `terrain`。
required final String iconName,
required final Map<String, GameAssistPlatformRules> platforms,
final int? steamAppId,
final int? sgdbGameId,
final String? iconAsset,
final String? gridAsset,
@Default(true) final bool showInPicker,
@Default(100) final int sort,

/// 选择器里标题下方的短说明。
@Default('') final String description,

/// 中文名；有则 UI 优先显示。
@Default('') final String nameZh,
}) = _GameAssistGameRules;

String get displayName =>
nameZh.trim().isNotEmpty ? nameZh.trim() : name;

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

/// 远程覆盖元数据；本机独有的 `inject` / 发现 / 广播标志保留。
GameAssistGameRules mergeFromRemote(GameAssistGameRules remote) {
final merged = <String, GameAssistPlatformRules>{...platforms};
remote.platforms.forEach((os, remotePlat) {
final localPlat = merged[os];
merged[os] = localPlat == null
? remotePlat
: localPlat.mergePreferRemote(remotePlat);
});
return copyWith(
id: remote.id,
name: remote.name,
colorHex: remote.colorHex,
iconName: remote.iconName,
steamAppId: remote.steamAppId ?? steamAppId,
sgdbGameId: remote.sgdbGameId ?? sgdbGameId,
iconAsset: remote.iconAsset ?? iconAsset,
gridAsset: remote.gridAsset ?? gridAsset,
showInPicker: remote.showInPicker,
sort: remote.sort,
description: remote.description.isNotEmpty
? remote.description
: description,
nameZh: remote.nameZh.isNotEmpty ? remote.nameZh : nameZh,
platforms: merged,
);
}
}

/// 发现本机开放游戏，并经 EasyTier 隧道向房间同伴宣告。
///
/// JSON：对象 = 一条；数组 = 多条。有块即启用。
@freezed
abstract class GameAssistLanGameDiscoverConfig with _$GameAssistLanGameDiscoverConfig {

const factory GameAssistLanGameDiscoverConfig({
@Default([]) final List<GameAssistLanGameDiscoverEntry> entries,
}) = _GameAssistLanGameDiscoverConfig;
const GameAssistLanGameDiscoverConfig._();

static const int intervalMs = 4000;
static const int ttlMs = 18000;

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

@freezed
abstract class GameAssistLanGameDiscoverEntry with _$GameAssistLanGameDiscoverEntry {

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
process: _stringList(json['process']),
window: _stringList(json['window']),
beaconPort: (json['beacon_port'] as num?)?.toInt() ?? 0,
);
}
const GameAssistLanGameDiscoverEntry._();

const factory GameAssistLanGameDiscoverEntry({
required final String id,
required final String label,

/// `static_port` | `udp_multicast` | `udp_probe` | `udp_broadcast` | `process_udp`
required final String type,
@Default(0) final int port,

/// 组播地址（不含端口）。
final String? multicast,
@Default(0) final int multicastPort,

/// `minecraft_motd` / `mindustry_server` / `scfa_lan` …
final String? parser,

/// `udp_probe` 探测包十六进制，如 `fe01`。
final String? probe,

/// 标题模板：`{player}` `{game}` `{label}` `{motd}` `{map}`。
final String? title,

/// `process_udp`：exe 名，如 `game.exe`。
@Default([]) final List<String> process,

/// `process_udp`：窗口标题关键字，如 `Forged Alliance`。
@Default([]) final List<String> window,

/// `process_udp`：本机代答发现口（FA 默认 15000）。
@Default(0) final int beaconPort,
}) = _GameAssistLanGameDiscoverEntry;

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
} catch (e) {
      appLogger.w('[GameAssistRules] 操作失败', error: e);
return null;

    }
}
}

List<String> _stringList(Object? raw) {
if (raw is List) {
return [
for (final e in raw)
if ('$e'.trim().isNotEmpty) '$e'.trim(),
];
}
final s = raw?.toString().trim();
if (s == null || s.isEmpty) return const [];
return [s];
}

/// EasyTier 传输档：对应客户端 UDP / TCP 两套 `[flags]`。缺省为 UDP。
enum GameAssistNetworkProtocol {
udp,
tcp;

static GameAssistNetworkProtocol parse(Object? raw) {
final s = '${raw ?? ''}'.trim().toLowerCase();
if (s == 'tcp') return tcp;
return udp;
}
}

/// EasyTier / 虚拟网相关开关（按平台）。
@freezed
abstract class GameAssistNetworkConfig with _$GameAssistNetworkConfig {
const GameAssistNetworkConfig._();

const factory GameAssistNetworkConfig({
/// 写入 TOML `[flags] enable_udp_broadcast_relay`（Windows）。
@Default(false) final bool enableUdpBroadcastRelay,

/// `tcp` / `udp`；未写则 UDP。
@Default(GameAssistNetworkProtocol.udp)
final GameAssistNetworkProtocol protocol,

/// JSON 是否显式写了 `protocol`（合并远程时避免把未写当成 UDP 覆盖本地）。
@Default(false) final bool protocolSpecified,
}) = _GameAssistNetworkConfig;

factory GameAssistNetworkConfig.fromJson(Map<String, dynamic> json) {
return GameAssistNetworkConfig(
enableUdpBroadcastRelay: json['enable_udp_broadcast_relay'] == true,
protocol: GameAssistNetworkProtocol.parse(json['protocol']),
protocolSpecified: json.containsKey('protocol'),
);
}
}

@freezed
abstract class GameAssistPlatformRules with _$GameAssistPlatformRules {

factory GameAssistPlatformRules.fromJson(Map<String, dynamic> json) {
final mw = json['magic_wall'];
final discover = json['lan_game_discover'];
final net = json['network'];
final inject = json['inject'];
return GameAssistPlatformRules(
network: net is Map
? GameAssistNetworkConfig.fromJson(Map<String, dynamic>.from(net))
: const GameAssistNetworkConfig(),
magicWall: GameAssistMagicWallConfig.parse(mw),
forwards: [
if (json['forwards'] is List)
for (final e in json['forwards'] as List)
if (e is Map)
GameAssistForwardRule.fromJson(Map<String, dynamic>.from(e)),
],
lanGameDiscover: GameAssistLanGameDiscoverConfig.tryParse(discover),
inject: inject is Map
? GameAssistInjectConfig.fromJson(Map<String, dynamic>.from(inject))
: null,
);
}
const GameAssistPlatformRules._();

const factory GameAssistPlatformRules({
@Default(GameAssistNetworkConfig()) final GameAssistNetworkConfig network,
required final GameAssistMagicWallConfig magicWall,
@Default([]) final List<GameAssistForwardRule> forwards,

/// 发现本机开放游戏并经 ET 宣告。
final GameAssistLanGameDiscoverConfig? lanGameDiscover,

/// 进房后自动检测进程并注入（Windows / Unity Mono）。
final GameAssistInjectConfig? inject,
}) = _GameAssistPlatformRules;

/// 魔法墙：按 exe 各自套规则。
List<GameAssistMagicWallExe> get magicWallTargets => magicWall.targets;

List<String> get magicWallProcessNames => [
for (final t in magicWallTargets) t.process,
];

/// 远程优先；缺项回退本地（CDN 尚未带 inject 时仍能注入）。
GameAssistPlatformRules mergePreferRemote(GameAssistPlatformRules remote) {
return copyWith(
network: GameAssistNetworkConfig(
enableUdpBroadcastRelay:
remote.network.enableUdpBroadcastRelay ||
network.enableUdpBroadcastRelay,
protocol: remote.network.protocolSpecified
? remote.network.protocol
: network.protocol,
protocolSpecified:
remote.network.protocolSpecified || network.protocolSpecified,
),
magicWall: remote.magicWall.isActive ? remote.magicWall : magicWall,
forwards: remote.forwards.isNotEmpty ? remote.forwards : forwards,
lanGameDiscover: remote.lanGameDiscover ?? lanGameDiscover,
inject: remote.inject ?? inject,
);
}
}

/// `platforms.<os>.inject`：自动找游戏进程并注入插件。
@freezed
abstract class GameAssistInjectConfig with _$GameAssistInjectConfig {

factory GameAssistInjectConfig.fromJson(Map<String, dynamic> json) {
final method = '${json['method'] ?? 'Init'}'.trim();
final delayRaw = json['delay_seconds'] ?? json['delaySeconds'];
final delay = delayRaw is num
? delayRaw.toInt()
: int.tryParse('${delayRaw ?? ''}') ?? 5;
return GameAssistInjectConfig(
type: '${json['type'] ?? ''}'.trim().toLowerCase(),
process: _stringList(json['process']),
window: _stringList(json['window']),
dll: '${json['dll'] ?? ''}'.trim(),
namespace: '${json['namespace'] ?? ''}'.trim(),
className: '${json['class'] ?? ''}'.trim(),
method: method.isEmpty ? 'Init' : method,
delaySeconds: delay < 0 ? 0 : delay,
);
}
const GameAssistInjectConfig._();

const factory GameAssistInjectConfig({
/// 目前仅 `mono`（Unity）。
required final String type,
@Default([]) final List<String> process,
@Default([]) final List<String> window,

/// 文件名，如 `AstralRaftNet.dll`。安装后在 `native/<gameId>/`。
@Default('') final String dll,
@Default('') final String namespace,
@Default('') final String className,
@Default('Init') final String method,

/// 首次发现进程后等待多少秒再注入，避免游戏未完全启动就注入导致崩溃。
@Default(5) final int delaySeconds,
}) = _GameAssistInjectConfig;

bool get isMono => type == 'mono' && dll.isNotEmpty && className.isNotEmpty;
}

/// `platforms.<os>.magic_wall`：按 exe 各自写防火墙规则。
@freezed
abstract class GameAssistMagicWallConfig with _$GameAssistMagicWallConfig {

const factory GameAssistMagicWallConfig({
@Default(false) final bool enabled,

/// 每个 exe 一套规则。
@Default([]) final List<GameAssistMagicWallExe> targets,
}) = _GameAssistMagicWallConfig;

factory GameAssistMagicWallConfig.parse(Object? raw) {
if (raw == null || raw == false || raw == true) return disabled;
if (raw is String) {
final name = raw.trim();
if (name.isEmpty) return disabled;
return GameAssistMagicWallConfig(
enabled: true,
targets: [GameAssistMagicWallExe(process: name)],
);
}
if (raw is List) {
return GameAssistMagicWallConfig._fromList(raw);
}
if (raw is Map) {
return GameAssistMagicWallConfig.fromJson(Map<String, dynamic>.from(raw));
}
return disabled;
}

factory GameAssistMagicWallConfig._fromList(List<dynamic> raw) {
final targets = <GameAssistMagicWallExe>[];
for (final e in raw) {
if (e is String) {
final name = e.trim();
if (name.isEmpty) continue;
targets.add(GameAssistMagicWallExe(process: name));
continue;
}
if (e is Map) {
targets.addAll(
GameAssistMagicWallExe.parseMany(Map<String, dynamic>.from(e)),
);
}
}
if (targets.isEmpty) return disabled;
return GameAssistMagicWallConfig(enabled: true, targets: targets);
}

factory GameAssistMagicWallConfig.fromJson(Map<String, dynamic> json) {
if (json['enabled'] == false) return disabled;

final keyed = <GameAssistMagicWallExe>[];
json.forEach((key, value) {
if (_reservedKeys.contains(key)) return;
final exe = GameAssistMagicWallExe.parseKeyed(key, value);
if (exe != null) keyed.add(exe);
});
if (keyed.isNotEmpty) {
return GameAssistMagicWallConfig(enabled: true, targets: keyed);
}

final process = _stringList(json['process']);
final rules = GameAssistMagicWallRule.parseList(json['rules']);
if (process.isEmpty) return disabled;
return GameAssistMagicWallConfig(
enabled: true,
targets: [
for (final name in process)
GameAssistMagicWallExe(process: name, rules: rules),
],
);
}
const GameAssistMagicWallConfig._();

static const GameAssistMagicWallConfig disabled = GameAssistMagicWallConfig();
static const Set<String> _reservedKeys = {'enabled', 'process', 'rules'};

bool get isActive => enabled && targets.isNotEmpty;
}

/// 单个 exe 的魔法墙。规则只作用在这个进程上。
@freezed
abstract class GameAssistMagicWallExe with _$GameAssistMagicWallExe {
const GameAssistMagicWallExe._();

const factory GameAssistMagicWallExe({
required final String process,
@Default([]) final List<GameAssistMagicWallRule> rules,
}) = _GameAssistMagicWallExe;

List<GameAssistMagicWallRule> get effectiveRules {
final enabled = [
for (final r in rules)
if (r.enabled) r,
];
if (enabled.isEmpty) return const [GameAssistMagicWallRule.defaultAllow];
return enabled;
}

static List<GameAssistMagicWallExe> parseMany(Map<String, dynamic> json) {
if (json['enabled'] == false) return const [];
final names = _stringList(json['process']);
if (names.isEmpty) return const [];
final rules = GameAssistMagicWallRule.parseList(json['rules']);
return [
for (final name in names)
GameAssistMagicWallExe(process: name, rules: rules),
];
}

static GameAssistMagicWallExe? parseKeyed(String exe, Object? value) {
final name = exe.trim();
if (name.isEmpty || value == true || value == false || value == null) {
return null;
}
if (value is List) {
final rules = GameAssistMagicWallRule.parseList(value);
if (rules.isEmpty) return null;
return GameAssistMagicWallExe(process: name, rules: rules);
}
if (value is Map) {
final map = Map<String, dynamic>.from(value);
if (map['enabled'] == false) return null;
final rules = map.containsKey('rules')
? GameAssistMagicWallRule.parseList(map['rules'])
: GameAssistMagicWallRule.parseList(map);
if (rules.isEmpty) return null;
return GameAssistMagicWallExe(process: name, rules: rules);
}
return null;
}
}

@freezed
abstract class GameAssistMagicWallRule with _$GameAssistMagicWallRule {

const factory GameAssistMagicWallRule({
@Default('') final String id,
@Default('allow') final String name,
@Default(true) final bool enabled,
@Default('allow') final String action,
@Default('both') final String protocol,
@Default('both') final String direction,
final String? remoteIp,
final String? localIp,
final String? remotePort,
final String? localPort,
final String? description,
}) = _GameAssistMagicWallRule;

factory GameAssistMagicWallRule.fromJson(Map<String, dynamic> json) {
return GameAssistMagicWallRule(
id: '${json['id'] ?? ''}'.trim(),
name: '${json['name'] ?? 'allow'}'.trim().isEmpty
? 'allow'
: '${json['name'] ?? 'allow'}'.trim(),
enabled: json['enabled'] != false,
action: '${json['action'] ?? 'allow'}'.trim().toLowerCase(),
protocol: '${json['protocol'] ?? 'both'}'.trim().toLowerCase(),
direction: '${json['direction'] ?? 'both'}'.trim().toLowerCase(),
remoteIp: _optionalString(json['remote_ip']),
localIp: _optionalString(json['local_ip']),
remotePort: _optionalString(json['remote_port']),
localPort: _optionalString(json['local_port']),
description: _optionalString(json['description']),
);
}
const GameAssistMagicWallRule._();

static const GameAssistMagicWallRule defaultAllow = GameAssistMagicWallRule();

static List<GameAssistMagicWallRule> parseList(Object? raw) {
final maps = <Map<String, dynamic>>[];
if (raw is List) {
for (final e in raw) {
if (e is Map) maps.add(Map<String, dynamic>.from(e));
}
} else if (raw is Map) {
maps.add(Map<String, dynamic>.from(raw));
}
return [for (final m in maps) GameAssistMagicWallRule.fromJson(m)];
}
}

@freezed
abstract class GameAssistForwardRule with _$GameAssistForwardRule {
const GameAssistForwardRule._();

const factory GameAssistForwardRule({
required final String listen,
required final String target,
@Default('tcp') final String proto,

/// 仅房主启动该转发。
@Default(true) final bool hostOnly,
}) = _GameAssistForwardRule;

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
