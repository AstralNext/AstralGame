import 'dart:io';

import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/room_share.dart';

/// 运行时注册 `astralgame://`（Windows HKCU）。
/// Android / iOS / macOS 已在系统清单声明；安装包另写 HKLM。
Future<void> registerJoinProtocol() async {
  if (!Platform.isWindows) return;
  try {
    final exe = Platform.resolvedExecutable;
    final command = '"$exe" "%1"';
    const root = 'HKCU\\Software\\Classes\\$kJoinAppScheme';
    await Process.run('reg', ['add', root, '/ve', '/d', 'URL:Astral Game', '/f']);
    await Process.run('reg', ['add', root, '/v', 'URL Protocol', '/d', '', '/f']);
    await Process.run('reg', [
      'add',
      '$root\\shell\\open\\command',
      '/ve',
      '/d',
      command,
      '/f',
    ]);
    appLogger.d('[JoinLink] 已注册 $kJoinAppScheme:// → $exe');
  } catch (e) {
    appLogger.d('[JoinLink] 注册 $kJoinAppScheme 失败: $e');
  }
}
