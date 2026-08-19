import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/windows_game_process.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_rust_core/astral_rust_core.dart';
import 'package:path/path.dart' as p;

/// Windows 房间辅助：按进程名自动魔法墙 / 按 JSON 启动 TCP 转发。
class RoomAssistService {
  RoomAssistService(this._p2p, this._rules);

  final P2PService _p2p;
  final GameAssistRulesService _rules;

  bool _magicWallStarted = false;
  final List<String> _appliedRuleIds = [];
  final Set<String> _appliedAppPaths = {};
  Timer? _magicWallTimer;
  List<GameAssistMagicWallExe> _magicWallTargets = const [];
  String _magicWallGameId = '';

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

    await _startMagicWall(platform, gameId);
    await _startForwards(platform.forwards, isHost: isHost, gameId: gameId);
  }

  Future<void> _startMagicWall(
    GameAssistPlatformRules platform,
    String gameId,
  ) async {
    await _stopMagicWallWatch();
    if (!platform.magicWall.isActive) {
      appLogger.d('[RoomAssist] 魔法墙未启用 game=$gameId');
      return;
    }

    final targets = platform.magicWallTargets;
    if (targets.isEmpty) {
      appLogger.w('[RoomAssist] 魔法墙已开但没有 exe game=$gameId');
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

    _magicWallGameId = gameId;
    _magicWallTargets = targets;
    _magicWallTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_tickMagicWall());
    });
    await _tickMagicWall();
    appLogger.i(
      '[RoomAssist] 魔法墙监视 exe=${[
        for (final t in targets) t.process,
      ].join(",")} game=$gameId',
    );
  }

  Future<void> _tickMagicWall() async {
    if (!_magicWallStarted || _magicWallTargets.isEmpty) return;
    final exeNames = [
      for (final t in _magicWallTargets) t.process,
    ];
    final procs = await listWindowsGameProcesses(
      exeNames: exeNames,
      windowNeedles: const [],
    );
    for (final proc in procs) {
      final path = proc.path.trim();
      if (path.isEmpty) continue;
      for (var t = 0; t < _magicWallTargets.length; t++) {
        final target = _magicWallTargets[t];
        if (!_exeMatches(path, target.process) &&
            !_exeMatches(proc.exe, target.process)) {
          continue;
        }
        final key =
            '${path.toLowerCase()}#$t#${target.process.toLowerCase()}';
        if (_appliedAppPaths.contains(key)) continue;
        final name = p.basename(path);
        var failed = false;
        final rules = target.effectiveRules;
        for (var i = 0; i < rules.length; i++) {
          final spec = rules[i];
          final specId = spec.id.isEmpty ? '$i' : spec.id;
          final ruleId =
              '${_magicWallGameId}_${key.hashCode.toUnsigned(32).toRadixString(16)}_$specId';
          try {
            await addMagicWallRule(
              rule: MagicWallRule(
                id: ruleId,
                name: spec.name,
                enabled: true,
                action: spec.action,
                protocol: spec.protocol,
                direction: spec.direction,
                appPath: path,
                remoteIp: spec.remoteIp,
                localIp: spec.localIp,
                remotePort: spec.remotePort,
                localPort: spec.localPort,
                description: spec.description ??
                    'Astral magic_wall $_magicWallGameId ${target.process}',
              ),
            );
            _appliedRuleIds.add(ruleId);
          } catch (e) {
            failed = true;
            appLogger.w(
              '[RoomAssist] 魔法墙规则失败 ${target.process} ${spec.name}: $e',
            );
          }
        }
        if (!failed) {
          _appliedAppPaths.add(key);
          appLogger.i(
            '[RoomAssist] 魔法墙已套到 $name (${target.process}) pid=${proc.pid}',
          );
        }
      }
    }
  }

  bool _exeMatches(String exe, String wantRaw) {
    final got = p.basename(exe.trim().toLowerCase());
    final stem = p.basenameWithoutExtension(got);
    final want = p.basename(wantRaw.trim().toLowerCase());
    if (want.isEmpty) return false;
    return got == want || stem == p.basenameWithoutExtension(want);
  }

  Future<void> _stopMagicWallWatch() async {
    _magicWallTimer?.cancel();
    _magicWallTimer = null;
    _magicWallTargets = const [];
    _magicWallGameId = '';
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
    await _stopMagicWallWatch();
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
    _appliedAppPaths.clear();

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
