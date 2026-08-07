import 'dart:io';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_rust_core/astral_rust_core.dart';

/// Windows 房间辅助：按本地 JSON 启动魔法墙 / TCP 转发。
class RoomAssistService {
  RoomAssistService(this._p2p, this._rules);

  final P2PService _p2p;
  final GameAssistRulesService _rules;

  bool _magicWallStarted = false;
  final List<String> _appliedRuleIds = [];

  static String get _platformKey => GameAssistRulesService.platformKey;

  Future<void> startForRoom({
    required bool isHost,
    required String gameId,
  }) async {
    // 当前仅实现 Windows 启动路径。
    if (!Platform.isWindows) return;
    await _p2p.ensureInitialized();
    final platform = await _rules.platformRules(gameId, _platformKey);
    if (platform == null) {
      appLogger.d('[RoomAssist] 无游戏规则 game=$gameId platform=$_platformKey');
      return;
    }

    await _startMagicWall(platform.magicWall, gameId);
    await _startForwards(platform.forwards, isHost: isHost, gameId: gameId);
  }

  Future<void> _startMagicWall(
    GameAssistMagicWallConfig mw,
    String gameId,
  ) async {
    if (!mw.enabled) {
      appLogger.d('[RoomAssist] 魔法墙未启用 game=$gameId');
      return;
    }

    try {
      await startMagicWall();
      _magicWallStarted = true;
      appLogger.i('[RoomAssist] 魔法墙引擎已启动');
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('已经在运行')) {
        _magicWallStarted = true;
        appLogger.i('[RoomAssist] 魔法墙已在运行');
      } else {
        appLogger.w('[RoomAssist] 魔法墙启动失败（可忽略）: $e');
        return;
      }
    }

    for (final rule in mw.rules) {
      if (!rule.enabled) continue;
      final ruleId = rule.id.trim().isEmpty
          ? '${gameId}_${rule.name}'
          : '${gameId}_${rule.id}';
      try {
        await addMagicWallRule(
          rule: MagicWallRule(
            id: ruleId,
            name: rule.name,
            enabled: true,
            action: rule.action,
            protocol: rule.protocol,
            direction: rule.direction,
            appPath: rule.appPath,
            remoteIp: rule.remoteIp,
            localIp: rule.localIp,
            remotePort: rule.remotePort,
            localPort: rule.localPort,
            description: rule.description,
          ),
        );
        _appliedRuleIds.add(ruleId);
        appLogger.i('[RoomAssist] 已应用魔法墙规则 $ruleId');
      } catch (e) {
        appLogger.w('[RoomAssist] 应用规则 $ruleId 失败: $e');
      }
    }
  }

  Future<void> _startForwards(
    List<GameAssistForwardRule> forwards, {
    required bool isHost,
    required String gameId,
  }) async {
    final toStart = <GameAssistForwardRule>[];
    for (final f in forwards) {
      if (f.hostOnly && !isHost) continue;
      if (f.listen.isEmpty || f.target.isEmpty) continue;
      // 自研 ForwardServer 目前仅 TCP
      if (f.proto != 'tcp') {
        appLogger.w(
          '[RoomAssist] 跳过非 TCP 转发 proto=${f.proto} listen=${f.listen}',
        );
        continue;
      }
      toStart.add(f);
    }
    if (toStart.isEmpty) {
      appLogger.d('[RoomAssist] 无 TCP 转发可启动 game=$gameId host=$isHost');
      return;
    }

    try {
      await stopAllForwardServers();
    } catch (_) {}

    for (final f in toStart) {
      try {
        final index = await createForwardServer(
          listenAddr: f.listen,
          forwardAddr: f.target,
        );
        appLogger.i(
          '[RoomAssist] TCP 转发 ${f.listen} -> ${f.target} (index=$index)',
        );
      } catch (e) {
        appLogger.w('[RoomAssist] TCP 转发失败 ${f.listen}: $e');
      }
    }
  }

  Future<void> stopAll() async {
    if (!Platform.isWindows) return;
    try {
      await _p2p.ensureInitialized();
    } catch (_) {
      return;
    }

    try {
      await stopAllForwardServers();
      appLogger.i('[RoomAssist] TCP 转发已全部停止');
    } catch (e) {
      appLogger.w('[RoomAssist] 停止 TCP 转发失败: $e');
    }

    for (final id in List<String>.from(_appliedRuleIds)) {
      try {
        await removeMagicWallRule(ruleId: id);
      } catch (_) {}
    }
    _appliedRuleIds.clear();

    if (_magicWallStarted) {
      try {
        await stopMagicWall();
        _magicWallStarted = false;
        appLogger.i('[RoomAssist] 魔法墙已停止');
      } catch (e) {
        appLogger.w('[RoomAssist] 停止魔法墙失败: $e');
      }
    }
  }
}
