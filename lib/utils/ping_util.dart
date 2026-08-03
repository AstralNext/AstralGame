import 'dart:io';

import 'package:astral_game/config/constants.dart';

class PingUtil {
  static Future<int?> ping(String server) async {
    try {
      final uri = Uri.tryParse(server.trim());
      final String hostname;
      final int port;

      if (uri != null && uri.hasScheme) {
        hostname = uri.host;
        if (hostname.isEmpty) return null;
        port = uri.hasPort
            ? uri.port
            : (uri.scheme == 'https' || uri.scheme == 'wss' ? 443 : 80);
      } else {
        // 旧输入格式：host:port
        final parts = server.split(':');
        hostname = parts[0];
        port = parts.length > 1 ? int.tryParse(parts[1]) ?? 80 : 80;
      }

      Socket? socket;
      final stopwatch = Stopwatch();

      try {
        stopwatch.start();
        socket = await Socket.connect(
          hostname,
          port,
          timeout: AppConstants.pingTimeout,
        );
        stopwatch.stop();
        final ms = stopwatch.elapsedMilliseconds;
        return ms > AppConstants.maxPingLatencyMs ? null : ms;
      } on SocketException {
        return null;
      } finally {
        socket?.destroy();
      }
    } catch (e) {
      return null;
    }
  }
}
