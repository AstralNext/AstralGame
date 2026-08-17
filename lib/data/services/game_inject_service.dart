import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/windows_game_process.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:path/path.dart' as p;

/// Windows：进房后按游戏找进程，用共用 Mono 注入器注入该游戏的插件 DLL。
class GameInjectService {
  GameInjectService(this._rules);

  final GameAssistRulesService _rules;

  Timer? _timer;
  GameAssistInjectConfig? _config;
  String _gameId = '';
  final Set<int> _injected = {};
  final Set<int> _inflight = {};
  final Map<int, DateTime> _retryAfter = {};
  /// 首次发现该 pid 的时间；用来做启动后延时注入。
  final Map<int, DateTime> _firstSeen = {};

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
    if (inject.process.isEmpty) {
      appLogger.w('[GameInject] 未配置 process，拒绝按窗口标题注入');
      return;
    }
    _gameId = gameId;
    _config = inject;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_tick());
    });
    await _tick();
    appLogger.i(
      '[GameInject] 已监视 exe=${inject.process.join(",")} '
      'dll=${inject.dll} delay=${inject.delaySeconds}s',
    );
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _config = null;
    _gameId = '';
    _injected.clear();
    _inflight.clear();
    _retryAfter.clear();
    _firstSeen.clear();
  }

  Future<void> _tick() async {
    final cfg = _config;
    if (cfg == null) return;
    if (!Platform.isWindows) return;

    // 只认 exe，不用窗口标题：标签页叫 Raft 的浏览器也会中招。
    final procs = await listWindowsGameProcesses(
      exeNames: cfg.process,
      windowNeedles: const [],
    );
    final alive = <int>{};
    final now = DateTime.now();
    for (final proc in procs) {
      if (proc.pid <= 0) continue;
      if (_isUnsafeInjectTarget(proc.exe)) {
        appLogger.d(
          '[GameInject] 跳过非游戏进程 ${proc.exe} pid=${proc.pid}',
        );
        continue;
      }
      if (!_exeAllowed(proc.exe, cfg.process)) continue;
      alive.add(proc.pid);
      if (_injected.contains(proc.pid) || _inflight.contains(proc.pid)) {
        continue;
      }
      final waitUntil = _retryAfter[proc.pid];
      if (waitUntil != null && now.isBefore(waitUntil)) {
        continue;
      }
      final firstSeen = _firstSeen.putIfAbsent(proc.pid, () {
        appLogger.i(
          '[GameInject] 发现 ${proc.exe} pid=${proc.pid}'
          '${proc.title.isEmpty ? "" : " title=${proc.title}"}'
          '，等待 ${cfg.delaySeconds}s 后再注入',
        );
        return now;
      });
      final elapsed = now.difference(firstSeen);
      final need = Duration(seconds: cfg.delaySeconds);
      if (elapsed < need) {
        continue;
      }
      _inflight.add(proc.pid);
      unawaited(_injectPid(proc.pid, proc.exe, cfg));
    }
    _injected.removeWhere((pid) => !alive.contains(pid));
    _retryAfter.removeWhere((pid, _) => !alive.contains(pid));
    _firstSeen.removeWhere((pid, _) => !alive.contains(pid));
  }

  Future<void> _injectPid(
    int pid,
    String exe,
    GameAssistInjectConfig cfg,
  ) async {
    try {
      final injector = _findInjector();
      final dll = _findDll(cfg.dll, _gameId);
      if (injector == null || dll == null) {
        appLogger.w(
          '[GameInject] 缺少注入文件 injector=$injector dll=$dll',
        );
        return;
      }
      appLogger.i('[GameInject] 注入 $exe pid=$pid');
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
        _retryAfter.remove(pid);
        appLogger.i('[GameInject] 成功 $exe pid=$pid $out');
      } else {
        final monoWait = out.contains('mono.dll not found');
        _retryAfter[pid] = DateTime.now().add(
          Duration(seconds: monoWait ? 10 : 4),
        );
        appLogger.w(
          '[GameInject] 失败 $exe pid=$pid code=${result.exitCode} $out',
        );
      }
    } catch (e) {
      _retryAfter[pid] = DateTime.now().add(const Duration(seconds: 6));
      appLogger.w('[GameInject] 异常 pid=$pid: $e');
    } finally {
      _inflight.remove(pid);
    }
  }

  bool _exeAllowed(String exe, List<String> names) {
    if (names.isEmpty) return false;
    final got = p.basename(exe.trim().toLowerCase());
    final stem = p.basenameWithoutExtension(got);
    for (final raw in names) {
      final want = p.basename(raw.trim().toLowerCase());
      if (want.isEmpty) continue;
      if (got == want) return true;
      if (stem == p.basenameWithoutExtension(want)) return true;
    }
    return false;
  }

  static const _unsafeExes = {
    'chrome.exe',
    'msedge.exe',
    'firefox.exe',
    'iexplore.exe',
    'brave.exe',
    'opera.exe',
    'vivaldi.exe',
    'chromium.exe',
    'qqbrowser.exe',
    '360chrome.exe',
    '360se.exe',
    'sogouexplorer.exe',
    'steam.exe',
    'steamwebhelper.exe',
  };

  bool _isUnsafeInjectTarget(String exe) {
    return _unsafeExes.contains(p.basename(exe.trim().toLowerCase()));
  }

  String? _findInjector() {
    for (final dir in _injectorDirs()) {
      final exe = File(p.join(dir, 'astral_mono_inject.exe'));
      if (exe.existsSync()) return exe.path;
    }
    return null;
  }

  String? _findDll(String relative, String gameId) {
    final name = p.basename(relative);
    final nested = relative.replaceAll('\\', '/');
    for (final dir in _dllDirs(gameId)) {
      final direct = File(p.join(dir, name));
      if (direct.existsSync()) return direct.path;
      final nestedFile = File(p.join(dir, nested));
      if (nestedFile.existsSync()) return nestedFile.path;
    }
    return null;
  }

  List<String> _injectorDirs() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final root = Directory.current.path;
    return [
      p.join(exeDir, 'native', 'inject'),
      exeDir,
      p.join(root, 'tools', 'mono_inject', 'target', 'release'),
      p.join(root, 'tools', 'mono_inject', 'bin'),
      // 旧包：注入器和 Raft 插件曾放在一起。
      p.join(exeDir, 'native', 'raft'),
    ];
  }

  List<String> _dllDirs(String gameId) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final root = Directory.current.path;
    final id = gameId.trim().toLowerCase();
    return [
      if (id.isNotEmpty) p.join(root, 'tools', '${id}_astral_net', 'dist'),
      if (id.isNotEmpty) p.join(root, 'tools', '${id}_astral_net', 'bin', 'plugin'),
      if (id.isNotEmpty) p.join(exeDir, 'native', id),
      p.join(exeDir, 'native', 'raft'),
      exeDir,
      p.join(root, 'tools', 'raft_astral_net', 'dist'),
      p.join(root, 'tools', 'raft_astral_net', 'bin', 'plugin'),
    ];
  }
}
