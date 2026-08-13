import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/windows_game_process.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:path/path.dart' as p;

/// Windows：进 Raft 房间后自动找进程并用 Rust mono 注入器注入插件。
class GameInjectService {
  GameInjectService(this._rules);

  final GameAssistRulesService _rules;

  Timer? _timer;
  GameAssistInjectConfig? _config;
  final Set<int> _injected = {};
  final Set<int> _inflight = {};

  Future<void> startForRoom({required String gameId}) async {
    await stop();
    if (!Platform.isWindows) return;
    await _rules.ensureLoaded();
    final platform = await _rules.platformRules(
      gameId,
      GameAssistRulesService.platformKey,
    );
    final inject = platform?.inject;
    if (inject == null || !inject.isMono) {
      appLogger.d('[GameInject] 未配置 mono 注入 game=$gameId');
      return;
    }
    _config = inject;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_tick());
    });
    await _tick();
    appLogger.i(
      '[GameInject] 已监视 ${inject.process.join(",")} dll=${inject.dll}',
    );
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _config = null;
    _injected.clear();
    _inflight.clear();
  }

  Future<void> _tick() async {
    final cfg = _config;
    if (cfg == null) return;
    if (!Platform.isWindows) return;

    final procs = await listWindowsGameProcesses(
      exeNames: cfg.process,
      windowNeedles: cfg.window,
    );
    final alive = <int>{};
    for (final proc in procs) {
      if (proc.pid <= 0) continue;
      alive.add(proc.pid);
      if (_injected.contains(proc.pid) || _inflight.contains(proc.pid)) {
        continue;
      }
      _inflight.add(proc.pid);
      unawaited(_injectPid(proc.pid, cfg));
    }
    _injected.removeWhere((pid) => !alive.contains(pid));
  }

  Future<void> _injectPid(int pid, GameAssistInjectConfig cfg) async {
    try {
      final injector = _findInjector();
      final dll = _findDll(cfg.dll);
      if (injector == null || dll == null) {
        appLogger.w(
          '[GameInject] 缺少注入文件 injector=$injector dll=$dll',
        );
        return;
      }
      appLogger.i('[GameInject] 注入 pid=$pid dll=$dll');
      final result = await Process.run(
        injector,
        [
          '--pid',
          '$pid',
          '--dll',
          dll,
          '--namespace',
          cfg.namespace,
          '--class',
          cfg.className,
          '--method',
          cfg.method,
        ],
        runInShell: false,
      );
      final out = '${result.stdout}\n${result.stderr}'.trim();
      if (result.exitCode == 0) {
        _injected.add(pid);
        appLogger.i('[GameInject] 成功 pid=$pid $out');
      } else {
        appLogger.w(
          '[GameInject] 失败 pid=${pid} code=${result.exitCode} $out',
        );
      }
    } catch (e) {
      appLogger.w('[GameInject] 异常 pid=$pid: $e');
    } finally {
      _inflight.remove(pid);
    }
  }

  String? _findInjector() {
    for (final dir in _searchDirs()) {
      final exe = File(p.join(dir, 'astral_mono_inject.exe'));
      if (exe.existsSync()) return exe.path;
    }
    return null;
  }

  String? _findDll(String relative) {
    final name = p.basename(relative);
    for (final dir in _searchDirs()) {
      final direct = File(p.join(dir, name));
      if (direct.existsSync()) return direct.path;
      final nested = File(p.join(dir, relative.replaceAll('\\', '/')));
      if (nested.existsSync()) return nested.path;
    }
    final plugin = File(
      p.join(
        Directory.current.path,
        'tools',
        'raft_astral_net',
        'bin',
        'plugin',
        name,
      ),
    );
    if (plugin.existsSync()) return plugin.path;
    return null;
  }

  List<String> _searchDirs() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return [
      p.join(exeDir, 'native', 'raft'),
      p.join(exeDir, 'raft'),
      exeDir,
      p.join(
        Directory.current.path,
        'tools',
        'raft_astral_net',
        'bin',
        'injector_rs',
      ),
      p.join(
        Directory.current.path,
        'tools',
        'raft_astral_net',
        'bin',
        'plugin',
      ),
      p.join(
        Directory.current.path,
        'tools',
        'raft_astral_net',
        'dist',
      ),
      p.join(
        Directory.current.path,
        'tools',
        'raft_astral_net',
        'injector_rs',
        'target',
        'release',
      ),
    ];
  }
}
