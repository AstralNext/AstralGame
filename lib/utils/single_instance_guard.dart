import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 桌面端进程级单实例守卫（macOS）。
///
/// Windows 在 [windows/runner/single_instance.cpp] 原生互斥；
/// Linux 通过移除 `G_APPLICATION_NON_UNIQUE` 由 GTK 单实例处理。
class SingleInstanceGuard {
  SingleInstanceGuard._();

  static RandomAccessFile? _lockHandle;

  static Future<bool> tryAcquire() async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      return true;
    }
    if (!Platform.isMacOS) {
      return true;
    }

    final lockPath = _lockFilePath();
    final file = File(lockPath);
    try {
      await file.parent.create(recursive: true);
      _lockHandle = await file.open(mode: FileMode.write);
      await _lockHandle!.lock(FileLock.exclusive);
      await _lockHandle!.setPosition(0);
      await _lockHandle!.writeString('${pid}\n');
      await _lockHandle!.flush();
      return true;
    } on FileSystemException {
      await _activateExistingMacApp();
      return false;
    }
  }

  static String _lockFilePath() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, '.astral_game', 'single_instance.lock');
    }
    return p.join(
      Directory.systemTemp.path,
      'astral_game.single_instance.lock',
    );
  }

  static Future<void> _activateExistingMacApp() async {
    try {
      await Process.run('open', ['-a', 'Astral Game']);
    } catch (_) {
      // 激活失败时仍退出第二实例，避免多开。
    }
  }
}
