import 'dart:io';

import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';

const kAliyunNtpHost = 'pool.ntp.org';
const kAliyunNtpPeer = 'pool.ntp.org,0x9';

/// Windows：启动后校准系统时间源。非 Windows 为空操作。
Future<void> ensureWindowsAliyunNtp() async {
  if (!RuntimePlatform.isWindows) return;
  try {
    await _ensureAliyunNtp().timeout(const Duration(seconds: 20));
  } catch (e) {
    appLogger.w('[TimeSync] $e');
  }
}

Future<void> _ensureAliyunNtp() async {
  await _run('sc', const ['config', 'w32time', 'start=', 'auto']);
  await _run('sc', const ['start', 'w32time']);

  final params = await _run(
    'reg',
    const [
      'query',
      r'HKLM\SYSTEM\CurrentControlSet\Services\W32Time\Parameters',
    ],
  );
  final ntpServer = parseRegSzValue(params.stdout.toString(), 'NtpServer');
  final type = parseRegSzValue(params.stdout.toString(), 'Type');
  if (alreadyUsingAliyunNtp(ntpServer: ntpServer, type: type)) {
    appLogger.i('[TimeSync] NTP already $kAliyunNtpHost');
    return;
  }

  appLogger.i(
    '[TimeSync] NTP is type=${type ?? "?"} server=${ntpServer ?? "?"} → $kAliyunNtpPeer',
  );
  final config = await _run('w32tm', [
    '/config',
    '/manualpeerlist:$kAliyunNtpPeer',
    '/syncfromflags:manual',
    '/reliable:yes',
    '/update',
  ]);
  if (config.exitCode != 0) {
    final detail = '${config.stdout}\n${config.stderr}'.trim();
    appLogger.w('[TimeSync] w32tm /config 失败: $detail');
    return;
  }

  final resync = await _run('w32tm', const ['/resync', '/force', '/nowait']);
  if (resync.exitCode != 0) {
    final detail = '${resync.stdout}\n${resync.stderr}'.trim();
    appLogger.w('[TimeSync] w32tm /resync 失败: $detail');
    return;
  }
  appLogger.i('[TimeSync] set NTP to $kAliyunNtpPeer and resync requested');
}

Future<ProcessResult> _run(String exe, List<String> args) {
  return Process.run(exe, args);
}

/// `reg query` 单行：`NtpServer    REG_SZ    time.windows.com,0x9`
String? parseRegSzValue(String stdout, String valueName) {
  final want = valueName.toLowerCase();
  for (final raw in stdout.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 3) continue;
    if (parts[0].toLowerCase() != want) continue;
    return parts.sublist(2).join(' ').trim();
  }
  return null;
}

String? ntpHostFromPeerList(String raw) {
  final first = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .firstOrNull;
  if (first == null) return null;
  final host = first.split(',').first.trim();
  return host.isEmpty ? null : host.toLowerCase();
}

bool alreadyUsingAliyunNtp({required String? ntpServer, required String? type}) {
  if (ntpServer == null || type == null) return false;
  if (type.trim().toUpperCase() != 'NTP') return false;
  return ntpHostFromPeerList(ntpServer) == kAliyunNtpHost;
}
