import 'dart:io';

import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/utils/logger.dart';

/// 防止「本机注入组播 → 再被发现器吃回去」的风暴。
abstract final class LanInjectGuard {
  static final Set<String> _keys = {};

  static String _key(int port, String motd) => '$port|${motd.trim()}';

  static void replaceEntries(Iterable<(int port, String motd)> entries) {
    _keys
      ..clear()
      ..addAll([
        for (final e in entries)
          if (e.$2.trim().isNotEmpty) _key(e.$1, e.$2),
      ]);
  }

  static void clear() => _keys.clear();

  static bool isLoopbackSource(String? ip) {
    final s = (ip ?? '').trim();
    if (s.isEmpty) return false;
    if (kLoopbackIpSet.contains(s)) return true;
    try {
      return InternetAddress(s).isLoopback;
    } catch (e) {
      appLogger.d('[LanInjectGuard] 解析 IP 失败 $s: $e');
      return false;
    }
  }

  static bool shouldIgnoreDiscovery({
    required String motd,
    String? sourceIp,
    int? gamePort,
  }) {
    if (isLoopbackSource(sourceIp)) return true;
    final m = motd.trim();
    if (m.isEmpty) return false;
    if (gamePort != null && gamePort > 0) {
      return _keys.contains(_key(gamePort, m));
    }
    return _keys.any((k) => k.endsWith('|$m'));
  }
}
