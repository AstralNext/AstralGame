import 'dart:io';

import 'package:astral_game/utils/logger.dart';
import 'package:astral_rust_core/astral_rust_core.dart' as rust;

/// 本机某个游戏进程及其 UDP 监听口（Windows）。
class WindowsGameProcess {
  const WindowsGameProcess({
    required this.pid,
    required this.exe,
    required this.title,
    required this.path,
    required this.udpPorts,
  });

  final int pid;
  final String exe;
  final String title;
  final String path;
  final List<int> udpPorts;
}

/// 用进程名 / 窗口标题找游戏，并列出其 UDP 口（Win32，走 rust_core）。
Future<List<WindowsGameProcess>> listWindowsGameProcesses({
  List<String> exeNames = const [],
  List<String> windowNeedles = const [],
}) async {
  if (!Platform.isWindows) return const [];
  final exes = [
    for (final e in exeNames)
      if (e.trim().isNotEmpty) e.trim().toLowerCase(),
  ];
  final windows = [
    for (final w in windowNeedles)
      if (w.trim().isNotEmpty) w.trim(),
  ];
  if (exes.isEmpty && windows.isEmpty) return const [];

  try {
    final rows = await rust.listGameProcesses(
      exeNames: exes,
      windowNeedles: windows,
    );
    return [
      for (final r in rows)
        if (r.pid > 0)
          WindowsGameProcess(
            pid: r.pid,
            exe: r.exe,
            title: r.title,
            path: r.path,
            udpPorts: List<int>.from(r.udpPorts),
          ),
    ];
  } catch (e) {
    appLogger.d('[WinProc] 枚举失败: $e');
    return const [];
  }
}
