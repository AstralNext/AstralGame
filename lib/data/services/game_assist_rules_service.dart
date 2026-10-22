import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:signals/signals_core.dart';

/// `platforms.android.lan_nat`：把房主虚拟 IP 映射成玩家物理网段里的假地址。
///
/// 适配那些「能看到房间、但加入时不向虚拟网地址发包」的老游戏。
class GameLanNatRule {
  const GameLanNatRule({required this.ports});

  final List<int> ports;

  static GameLanNatRule? tryParse(Object? json) {
    if (json is! Map || json['enabled'] != true) return null;
    final raw = json['ports'];
    final ports = <int>[];
    if (raw is List) {
      for (final item in raw) {
        final v = item is int ? item : int.tryParse('$item');
        if (v != null && v > 0 && v <= 65535) ports.add(v);
      }
    }
    if (ports.isEmpty) return null;
    return GameLanNatRule(ports: List<int>.unmodifiable(ports));
  }
}

/// 从远程加载游戏规则（目录 + 平台辅助）；失败时回退本地 asset。
/// 仓库根或程序旁的 [testDirName] 里若有 JSON，优先用测试文件，不再拉线上。
///
/// 启动时异步加载：本地 asset → 测试目录 → 磁盘 ETag 缓存 → 远程，不阻塞 [runApp]。
class GameAssistRulesService {
  GameAssistRulesService({
    http.Client? client,
    List<Directory>? testRuleDirs,
    Directory? cacheDir,
    Future<String?> Function()? assetLoader,
  }) : _client = client ?? http.Client(),
       _testRuleDirs = testRuleDirs,
       _cacheDir = cacheDir,
       _assetLoader = assetLoader;

  /// 线上规则。
  static const remoteUrl = kAstralGameRulesUrl;

  /// 离线回退。
  static const assetPath = 'assets/games/rules.json';

  /// 测试覆盖目录名（工作目录或可执行文件旁）。
  static const testDirName = 'gamerules';

  static const _cacheJsonName = 'gamerules-cache.json';
  static const _cacheEtagName = 'gamerules-cache.etag';

  /// 相对路径图片的解析基准。
  static const mediaBaseUrl = kAstralGameMediaBaseUrl;

  final http.Client _client;
  final List<Directory>? _testRuleDirs;
  final Directory? _cacheDir;
  final Future<String?> Function()? _assetLoader;

  GameAssistRulesCatalog? _catalog;
  Future<GameAssistRulesCatalog>? _loadFuture;
  final Map<String, GameLanNatRule> _lanNatRules = <String, GameLanNatRule>{};
  final Completer<void> _assetApplied = Completer<void>();

  /// 本地 asset + 磁盘缓存落地（不含远程）；进房等实时路径只等这个。
  final Completer<void> _localApplied = Completer<void>();

  /// 目录每次成功应用后递增，供 UI `Watch`。
  final catalogRevision = signal(0);

  GameAssistRulesCatalog? get catalog => _catalog;

  Future<GameAssistRulesCatalog> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<GameAssistRulesCatalog> _load() async {
    // 1) 本地先落地，尽快有可选游戏（即使只有「其他」）。
    final assetRaw = await _loadAssetFallback();
    if (assetRaw != null) {
      _applyRaw(assetRaw, source: 'asset');
    }
    if (!_assetApplied.isCompleted) _assetApplied.complete();

    // 2) 测试目录有 JSON 则覆盖并跳过远程。
    if (await _applyTestDir()) {
      _completeLocal();
      return _catalog!;
    }

    // 3) 上次远程成功结果（ETag 缓存），弱网也能用较新目录。
    await _applyDiskCache();
    _completeLocal();

    // 4) 远程覆盖（If-None-Match；失败则保留 cache / asset）。
    final remote = await _fetchRemote();
    if (remote.notModified) {
      appLogger.i('[GameAssistRules] 远程未变化 (304)');
    } else if (remote.body != null) {
      _applyRaw(remote.body!, source: 'remote');
      await _writeDiskCache(remote.body!, remote.etag);
    }

    if (_catalog != null) return _catalog!;

    appLogger.e('[GameAssistRules] 本地与远程均不可用');
    const empty = GameAssistRulesCatalog(version: 0, games: []);
    _applyCatalog(empty);
    return empty;
  }

  void _applyRaw(String raw, {required String source}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('gamerules.json root must be object');
      }
      _applyLanNatRules(decoded);
      final incoming = GameAssistRulesCatalog.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      final catalog = source != 'asset' && _catalog != null
          ? _mergeCatalogs(local: _catalog!, remote: incoming)
          : incoming;
      _applyCatalog(catalog);
      appLogger.i(
        '[GameAssistRules] 已应用 ($source) v${catalog.version} '
        'games=${catalog.games.length}',
      );
    } catch (e, st) {
      appLogger.e(
        '[GameAssistRules] 解析失败 ($source): $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _applyLanNatRules(Map decoded) {
    final games = decoded['games'];
    if (games is! List) return;
    for (final game in games) {
      if (game is! Map) continue;
      final id = '${game['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final platforms = game['platforms'];
      final android = platforms is Map ? platforms['android'] : null;
      // 远程目录没带这个字段时保留已有规则（本地 asset 可能先给了）。
      if (android is! Map || !android.containsKey('lan_nat')) continue;
      final rule = GameLanNatRule.tryParse(android['lan_nat']);
      if (rule == null) {
        _lanNatRules.remove(id);
      } else {
        _lanNatRules[id] = rule;
      }
    }
  }

  /// 该游戏是否需要 LAN NAT（仅 Android 生效）。
  GameLanNatRule? lanNatRule(String gameId) => _lanNatRules[gameId];

  /// 等本地 asset 规则落地；只等 asset，不等远程。
  Future<void> ensureAssetLoaded() {
    ensureLoaded();
    return _assetApplied.future;
  }

  /// 等本地 asset + 磁盘缓存规则落地，不等远程。
  ///
  /// 建/进房、辅助服务启动等实时路径只等这个：冷启动远程目录可能很慢
  /// （最长 [kGameRulesTimeout]），不能让它拖住进房；远程结果到了会更新
  /// 目录供后续使用。
  Future<void> ensureLocalLoaded() {
    ensureLoaded();
    return _localApplied.future;
  }

  void _completeLocal() {
    if (!_localApplied.isCompleted) _localApplied.complete();
  }

  /// 远程 / 测试覆盖同 id；本地独有（如尚未上 CDN 的 inject）保留。
  GameAssistRulesCatalog _mergeCatalogs({
    required GameAssistRulesCatalog local,
    required GameAssistRulesCatalog remote,
  }) {
    final byId = <String, GameAssistGameRules>{
      for (final g in local.games) g.id: g,
    };
    for (final g in remote.games) {
      final existing = byId[g.id];
      byId[g.id] = existing == null ? g : existing.mergeFromRemote(g);
    }
    final games = byId.values.toList()
      ..sort((a, b) => a.sort.compareTo(b.sort));
    return GameAssistRulesCatalog(version: remote.version, games: games);
  }

  void _applyCatalog(GameAssistRulesCatalog catalog) {
    _catalog = catalog;
    GameCatalog.applyFromRules(catalog);
    catalogRevision.value = catalogRevision.value + 1;
  }

  Future<bool> _applyTestDir() async {
    final files = listTestRuleFiles(_testRuleDirs ?? defaultTestRuleDirs());
    if (files.isEmpty) return false;
    final revisionBefore = catalogRevision.value;
    for (final file in files) {
      try {
        _applyRaw(await file.readAsString(), source: 'test:${file.path}');
      } catch (e) {
        appLogger.w('[GameAssistRules] 读取测试规则失败 ${file.path}: $e');
      }
    }
    if (catalogRevision.value == revisionBefore) {
      appLogger.w('[GameAssistRules] 测试目录有 JSON 但都未解析成功，继续远程');
      return false;
    }
    appLogger.i(
      '[GameAssistRules] 已用测试目录，跳过远程 ${files.map((f) => f.path).join(', ')}',
    );
    return true;
  }

  /// 工作目录 `gamerules/`，以及可执行文件旁 `gamerules/`。
  static List<Directory> defaultTestRuleDirs() {
    final dirs = <Directory>[];
    try {
      dirs.add(Directory(p.join(Directory.current.path, testDirName)));
    } catch (e) {
      appLogger.w('[RulesService] 操作失败', error: e);
    }
    try {
      if (RuntimePlatform.isDesktop) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        dirs.add(Directory(p.join(exeDir, testDirName)));
      }
    } catch (e) {
      appLogger.w('[RulesService] 操作失败', error: e);
    }
    return dirs;
  }

  /// 测试目录里的 JSON：`gamerules.json`、`rules.json` 优先，其余按文件名。
  static List<File> listTestRuleFiles(Iterable<Directory> dirs) {
    final out = <File>[];
    final seen = <String>{};
    for (final dir in dirs) {
      try {
        if (!dir.existsSync()) continue;
        final files =
            dir
                .listSync()
                .whereType<File>()
                .where((f) => p.extension(f.path).toLowerCase() == '.json')
                .toList()
              ..sort((a, b) {
                final ra = _testJsonRank(p.basename(a.path));
                final rb = _testJsonRank(p.basename(b.path));
                if (ra != rb) return ra.compareTo(rb);
                return p
                    .basename(a.path)
                    .toLowerCase()
                    .compareTo(p.basename(b.path).toLowerCase());
              });
        for (final file in files) {
          final key = p.normalize(file.absolute.path).toLowerCase();
          if (seen.add(key)) out.add(file);
        }
      } catch (e) {
        appLogger.w('[GameAssistRules] 扫描测试目录失败 ${dir.path}: $e');
      }
    }
    return out;
  }

  static int _testJsonRank(String name) {
    final n = name.toLowerCase();
    if (n == 'gamerules.json') return 0;
    if (n == 'rules.json') return 1;
    return 2;
  }

  Future<_RemoteRulesFetch> _fetchRemote() async {
    try {
      final etag = await _readDiskEtag();
      final headers = <String, String>{
        if (etag != null && etag.isNotEmpty) 'If-None-Match': etag,
      };
      final res = await _client
          .get(Uri.parse(remoteUrl), headers: headers)
          .timeout(kGameRulesTimeout);
      if (res.statusCode == 304) {
        return const _RemoteRulesFetch(notModified: true);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        appLogger.w('[GameAssistRules] 远程 HTTP ${res.statusCode}，保留本地目录');
        return const _RemoteRulesFetch();
      }
      appLogger.i('[GameAssistRules] 已从远程加载 $remoteUrl');
      return _RemoteRulesFetch(
        body: utf8.decode(res.bodyBytes),
        etag: res.headers['etag'],
      );
    } catch (e) {
      appLogger.w('[GameAssistRules] 远程加载失败: $e，保留本地目录');
      return const _RemoteRulesFetch();
    }
  }

  File? get _cacheJsonFile {
    final dir = _cacheDir;
    if (dir == null) return null;
    return File(p.join(dir.path, _cacheJsonName));
  }

  File? get _cacheEtagFile {
    final dir = _cacheDir;
    if (dir == null) return null;
    return File(p.join(dir.path, _cacheEtagName));
  }

  Future<void> _applyDiskCache() async {
    final file = _cacheJsonFile;
    if (file == null || !file.existsSync()) return;
    try {
      _applyRaw(await file.readAsString(), source: 'cache');
    } catch (e) {
      appLogger.w('[GameAssistRules] 读取磁盘缓存失败: $e');
    }
  }

  Future<void> _writeDiskCache(String body, String? etag) async {
    final jsonFile = _cacheJsonFile;
    if (jsonFile == null) return;
    try {
      await jsonFile.parent.create(recursive: true);
      await jsonFile.writeAsString(body, flush: true);
      final etagFile = _cacheEtagFile;
      if (etagFile != null) {
        await etagFile.writeAsString(etag?.trim() ?? '', flush: true);
      }
    } catch (e) {
      appLogger.w('[GameAssistRules] 写入磁盘缓存失败: $e');
    }
  }

  Future<String?> _readDiskEtag() async {
    final file = _cacheEtagFile;
    if (file == null || !file.existsSync()) return null;
    try {
      final raw = (await file.readAsString()).trim();
      return raw.isEmpty ? null : raw;
    } catch (e) {
      appLogger.w('[RulesService] 操作失败', error: e);
      return null;
    }
  }

  Future<String?> _loadAssetFallback() async {
    final injected = _assetLoader;
    if (injected != null) {
      return injected();
    }
    try {
      final raw = await rootBundle.loadString(assetPath);
      appLogger.i('[GameAssistRules] 使用本地 $assetPath');
      return raw;
    } catch (e) {
      appLogger.w('[GameAssistRules] 本地回退失败: $e');
      return null;
    }
  }

  /// 房间实时路径用本地规则（不等远程），避免冷启动进房被远程下载拖慢。
  Future<GameAssistPlatformRules?> platformRules(
    String gameId,
    String platform,
  ) async {
    await ensureLocalLoaded();
    return _catalog?.platformRules(gameId, platform);
  }

  Future<GameAssistGameRules?> gameRules(String gameId) async {
    await ensureLocalLoaded();
    return _catalog?.byId(gameId);
  }

  /// 该游戏是否要求 EasyTier UDP 广播转发（当前平台，回退 windows）。
  Future<bool> wantsUdpBroadcastRelay(String gameId) async {
    final rules = await gameRules(gameId);
    return rules?.networkFor(_platformKey).enableUdpBroadcastRelay == true;
  }

  /// EasyTier 传输档；未写 `network.protocol` 时为 UDP。
  Future<GameAssistNetworkProtocol> networkProtocol(String gameId) async {
    final rules = await gameRules(gameId);
    return rules?.networkFor(_platformKey).protocol ??
        GameAssistNetworkProtocol.udp;
  }

  /// 与 JSON `platforms` 键一致（如 `windows`）。
  static String get platformKey => _platformKey;

  static String get _platformKey {
    if (RuntimePlatform.isWindows) return 'windows';
    if (RuntimePlatform.isAndroid) return 'android';
    if (RuntimePlatform.isIOS) return 'ios';
    if (RuntimePlatform.isMacOS) return 'macos';
    if (RuntimePlatform.isLinux) return 'linux';
    return 'windows';
  }

  void close() => _client.close();
}

class _RemoteRulesFetch {
  const _RemoteRulesFetch({this.body, this.etag, this.notModified = false});

  final String? body;
  final String? etag;
  final bool notModified;
}
