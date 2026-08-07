import 'dart:convert';
import 'dart:io';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// 从远程加载游戏规则（目录 + 平台辅助）；失败时回退本地 asset。
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

  GameAssistRulesCatalog? get catalog => _catalog;

  Future<GameAssistRulesCatalog> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<GameAssistRulesCatalog> _load() async {
    try {
      final raw = await _fetchRemote() ?? await _loadAssetFallback();
      if (raw == null) {
        throw const FormatException('无法获取 gamerules.json');
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('gamerules.json root must be object');
      }
      final catalog = GameAssistRulesCatalog.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      _catalog = catalog;
      GameCatalog.applyFromRules(catalog);
      appLogger.i(
        '[GameAssistRules] 已加载 v${catalog.version} '
        'games=${catalog.games.length}',
      );
      return catalog;
    } catch (e, st) {
      appLogger.e('[GameAssistRules] 加载失败: $e', error: e, stackTrace: st);
      final empty = const GameAssistRulesCatalog(version: 0, games: []);
      _catalog = empty;
      GameCatalog.applyFromRules(empty);
      return empty;
    }
  }

  Future<String?> _fetchRemote() async {
    try {
      final res = await _client
          .get(Uri.parse(remoteUrl))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        appLogger.w(
          '[GameAssistRules] 远程 HTTP ${res.statusCode}，尝试本地回退',
        );
        return null;
      }
      appLogger.i('[GameAssistRules] 已从远程加载 $remoteUrl');
      return utf8.decode(res.bodyBytes);
    } catch (e) {
      appLogger.w('[GameAssistRules] 远程加载失败: $e，尝试本地回退');
      return null;
    }
  }

  Future<String?> _loadAssetFallback() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      appLogger.i('[GameAssistRules] 使用本地回退 $assetPath');
      return raw;
    } catch (e) {
      appLogger.w('[GameAssistRules] 本地回退也失败: $e');
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
