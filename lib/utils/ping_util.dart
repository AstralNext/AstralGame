import 'dart:io';
import 'dart:isolate';

import 'package:astral_game/config/constants.dart';
import 'package:astral_game/utils/icmp_echo.dart';

/// 进程内 ICMP Echo，不发起 TCP，也不调用系统 `ping`。
class PingUtil {
  PingUtil._();

  static Future<int?> ping(String server) async {
    final host = pingHostOf(server);
    if (host == null) return null;
    return pingHost(host);
  }

  static Future<int?> pingHost(String host) async {
    final ip = await resolvePingIpv4(host);
    if (ip == null) return null;
    final timeoutMs = AppConstants.pingTimeout.inMilliseconds;
    try {
      return await Isolate.run(() => icmpEchoRttMsSync(ip, timeoutMs));
    } catch (_) {
      return null;
    }
  }
}

/// 从服务器 URL / `host:port` 取出 ICMP 目标主机。
String? pingHostOf(String server) {
  final raw = server.trim();
  if (raw.isEmpty) return null;

  final uri = Uri.tryParse(raw);
  String? host;
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    host = uri.host;
  } else if (raw.startsWith('[')) {
    final end = raw.indexOf(']');
    if (end > 1) host = raw.substring(1, end);
  } else {
    final colon = raw.lastIndexOf(':');
    if (colon > 0 && int.tryParse(raw.substring(colon + 1)) != null) {
      host = raw.substring(0, colon);
    } else {
      host = raw;
    }
  }

  host = host?.trim();
  if (host == null || host.isEmpty) return null;
  if (host == '0.0.0.0' || host == '::' || host == '*') return null;
  if (host.startsWith('-') || RegExp(r'\s').hasMatch(host)) return null;
  return host;
}

Future<String?> resolvePingIpv4(String host) async {
  final parsed = InternetAddress.tryParse(host);
  if (parsed != null) {
    return parsed.type == InternetAddressType.IPv4 ? parsed.address : null;
  }
  try {
    final addrs =
        await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
    if (addrs.isNotEmpty) return addrs.first.address;
  } catch (_) {}
  return null;
}
