import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/services/windows_game_process.dart';

typedef WindowsProcessListener = void Function(List<WindowsGameProcess> procs);

class _WatchSub {
  _WatchSub(this.exeNames, this.onTick);
  final List<String> exeNames;
  final WindowsProcessListener onTick;
}

/// 合并注入 / 魔法墙的进程枚举：一次 FFI，多个订阅者。
class WindowsProcessWatch {
  static const interval = Duration(seconds: 2);

  Timer? _timer;
  bool _disposed = false;
  Future<void> _inflight = Future.value();
  final Map<Object, _WatchSub> _subs = {};

  void subscribe({
    required Object key,
    required List<String> exeNames,
    required WindowsProcessListener onTick,
  }) {
    if (_disposed) return;
    _subs[key] = _WatchSub(
      [
        for (final e in exeNames)
          if (e.trim().isNotEmpty) e.trim(),
      ],
      onTick,
    );
    if (!Platform.isWindows) return;
    _timer ??= Timer.periodic(interval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  void unsubscribe(Object key) {
    _subs.remove(key);
    if (_subs.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _subs.clear();
  }

  Future<void> _tick() {
    return _inflight = _inflight.then((_) => _tickOnce());
  }

  Future<void> _tickOnce() async {
    if (_disposed || _subs.isEmpty || !Platform.isWindows) return;
    final names = <String>{};
    final snapshot = List<_WatchSub>.from(_subs.values);
    for (final s in snapshot) {
      names.addAll(s.exeNames);
    }
    if (names.isEmpty) return;
    final procs = await listWindowsGameProcesses(
      exeNames: names.toList(growable: false),
    );
    if (_disposed) return;
    for (final s in snapshot) {
      if (_disposed) return;
      s.onTick([
        for (final p in procs)
          if (windowsExeMatchesAny(p, s.exeNames)) p,
      ]);
    }
  }
}
