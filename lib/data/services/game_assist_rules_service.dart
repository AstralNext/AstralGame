import 'dart:convert';
import 'dart:io';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:signals/signals_core.dart';

/// 从远程加载游戏规则（目录 + 平台辅助）；失败时回退本地 asset。
///
/// 启动时异步加载：先本地、再远程，不阻塞 [runApp]。
class GameAssistRulesService {
  GameAssistRulesService({http.Client? client}) : _client = client ?? http.Client();

  /// 线上规则。
  static const remoteUrl = kAstralGameRulesUrl;

  /// 离线回退。
  static const assetPath = 'assets/games/rules.json';

  /// 相对路径图片的解析基准。
  static const mediaBaseUrl = kAstralGameMediaBaseUrl;

  final http.Client _client;

  GameAssistRulesCatalog? _catalog;
  Future<GameAssistRulesCatalog>? _loadFuture;

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

    // 2) 远程覆盖（后台；失败则保留 asset）。
    final remoteRaw = await _fetchRemote();
    if (remoteRaw != null) {
      _applyRaw(remoteRaw, source: 'remote');
    }

    if (_catalog != null) return _catalog!;

    appLogger.e('[GameAssistRules] 本地与远程均不可用');
    final empty = const GameAssistRulesCatalog(version: 0, games: []);
    _applyCatalog(empty);
    return empty;
  }

  void _applyRaw(String raw, {required String source}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('gamerules.json root must be object');
      }
      final catalog = GameAssistRulesCatalog.fromJson(
        Map<String, dynamic>.from(decoded),
      );
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

  void _applyCatalog(GameAssistRulesCatalog catalog) {
    _catalog = catalog;
    GameCatalog.applyFromRules(catalog);
    catalogRevision.value = catalogRevision.value + 1;
  }

  Future<String?> _fetchRemote() async {
    try {
      final res = await _client
          .get(Uri.parse(remoteUrl))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        appLogger.w(
          '[GameAssistRules] 远程 HTTP ${res.statusCode}，保留本地目录',
        );
        return null;
      }
      appLogger.i('[GameAssistRules] 已从远程加载 $remoteUrl');
      return utf8.decode(res.bodyBytes);
    } catch (e) {
      appLogger.w('[GameAssistRules] 远程加载失败: $e，保留本地目录');
      return null;
    }
  }

  Future<String?> _loadAssetFallback() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      appLogger.i('[GameAssistRules] 使用本地 $assetPath');
      return raw;
    } catch (e) {
      appLogger.w('[GameAssistRules] 本地回退失败: $e');
      return null;
    }
  }

  Future<GameAssistPlatformRules?> platformRules(
    String gameId,
    String platform,
  ) async {
    final catalog = await ensureLoaded();
    return catalog.platformRules(gameId, platform);
  }

  Future<GameAssistGameRules?> gameRules(String gameId) async {
    final catalog = await ensureLoaded();
    return catalog.byId(gameId);
  }

  /// 该游戏是否要求 EasyTier UDP 广播转发（当前平台，回退 windows）。
  Future<bool> wantsUdpBroadcastRelay(String gameId) async {
    final rules = await gameRules(gameId);
    return rules?.networkFor(_platformKey).enableUdpBroadcastRelay == true;
  }

  /// 与 JSON `platforms` 键一致（如 `windows`）。
  static String get platformKey => _platformKey;

  static String get _platformKey {
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'windows';
  }
}
