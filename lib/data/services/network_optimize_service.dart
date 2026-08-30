import 'dart:io';

import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals.dart';

/// Windows：封装 SmartDNS 服务 + auto_dns_binder 的安装/卸载。
class NetworkOptimizeService {
  final installed = signal(false);
  final busy = signal(false);

  Future<void> refresh() async {
    if (!RuntimePlatform.isWindows) {
      installed.value = false;
      return;
    }
    final exe = findBinderExe();
    if (exe == null) {
      installed.value = false;
      return;
    }
    try {
      final result = await Process.run(
        exe,
        const ['status'],
      );
      installed.value = parseInstalled(result.stdout.toString());
    } catch (e) {
      appLogger.w('[NetworkOptimize] status 失败: $e');
      installed.value = false;
    }
  }

  Future<void> setEnabled(bool enable) async {
    if (!RuntimePlatform.isWindows) return;
    if (busy.value) return;
    busy.value = true;
    try {
      final exe = findBinderExe();
      if (exe == null) {
        throw StateError('找不到 auto_dns_binder.exe');
      }
      final result = await Process.run(
        exe,
        [enable ? 'install' : 'uninstall'],
      );
      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();
      if (stdout.trim().isNotEmpty) {
        appLogger.i('[NetworkOptimize] $stdout');
      }
      if (result.exitCode != 0) {
        final detail = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
        throw StateError(detail.isEmpty ? 'exit ${result.exitCode}' : detail);
      }
      await refresh();
      if (installed.value != enable) {
        throw StateError(enable ? '安装后服务未就绪' : '卸载后服务仍在');
      }
    } finally {
      busy.value = false;
    }
  }
}

bool parseInstalled(String stdout) {
  return stdout
      .split(RegExp(r'\r?\n'))
      .any((line) => line.trim() == 'installed=yes');
}

String? findBinderExe() {
  for (final dir in binderDirs()) {
    final exe = File(p.join(dir, 'auto_dns_binder.exe'));
    if (exe.existsSync()) return exe.path;
  }
  return null;
}

List<String> binderDirs() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final root = Directory.current.path;
  return [
    p.join(exeDir, 'native', 'dns'),
    exeDir,
    p.join(root, 'tools', 'auto_dns_binder', 'target', 'release'),
    p.join(root, 'tools', 'auto_dns_binder', 'bin'),
  ];
}
