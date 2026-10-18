import 'dart:convert';

import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/services.dart';

/// Android 悬浮窗：在线用户头像 / IP / 延迟。
class FloatingOverlayService {
  static const _channel = MethodChannel(
    'fan.astral.next.game/floating_overlay',
  );

  bool get isSupported => RuntimePlatform.isAndroid;

  Future<bool> canDrawOverlays() async {
    if (!isSupported) return false;
    final ok = await _channel.invokeMethod<bool>('canDrawOverlays');
    return ok ?? false;
  }

  Future<void> openOverlayPermissionSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openOverlayPermissionSettings');
  }

  Future<void> show() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('showOverlay');
  }

  Future<void> hide() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('hideOverlay');
  }

  Future<void> updatePayload({
    required bool connected,
    required List<EnhancedNodeInfo> users,
    Map<int, double> latencyByPeerId = const {},
  }) async {
    if (!isSupported) return;
    final payload = jsonEncode({
      'connected': connected,
      'users': users
          .map((node) => _encodeUser(node, latencyByPeerId[node.peerId]))
          .toList(),
    });
    await _channel.invokeMethod<void>('updateOverlay', {'payload': payload});
  }

  static Map<String, dynamic> _encodeUser(
    EnhancedNodeInfo node,
    double? liveLatencyMs,
  ) {
    final ip = node.hasValidIpv4 ? node.ipv4.split('/').first.trim() : '未分配 IP';
    // userNodes 的快照比较不含延迟，实时值来自独立的 linkMetrics signal。
    final latencyMs = (liveLatencyMs != null && liveLatencyMs > 0)
        ? liveLatencyMs
        : node.baseInfo.latencyMs;
    final map = <String, dynamic>{
      'peerId': node.peerId,
      'name': node.displayName,
      'ip': ip,
      'latencyMs': latencyMs,
    };
    final avatar = node.avatar;
    if (avatar != null && avatar.isNotEmpty) {
      map['avatarBase64'] = base64Encode(avatar);
    }
    return map;
  }

  /// 按设置开关与悬浮窗权限应用显示/隐藏并刷新数据。
  Future<void> applyFromAppState({
    required AppSettingsService settings,
    required NodeManagementService nodes,
  }) async {
    if (!isSupported) return;
    final enabled = settings.isFloatingOverlayEnabled();
    if (!enabled) {
      await hide();
      return;
    }
    if (!await canDrawOverlays()) {
      await hide();
      return;
    }

    final connected = nodes.isRunning;
    final users = nodes.userNodes.value
        .where((n) => !n.hostname.startsWith(AppConstants.publicServerHostname))
        .toList();
    final latencies = <int, double>{
      for (final user in users)
        user.peerId: nodes.linkMetricsOf(user.peerId).value.latencyMs,
    };

    await show();
    await updatePayload(
      connected: connected,
      users: users,
      latencyByPeerId: latencies,
    );
  }
}
