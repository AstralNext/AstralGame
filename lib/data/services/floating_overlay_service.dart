import 'dart:convert';
import 'dart:io';

import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/di.dart';
import 'package:flutter/services.dart';

/// Android 悬浮窗：在线用户头像 / IP / 延迟。
class FloatingOverlayService {
  static const _channel = MethodChannel(
    'fan.astral.next.game/floating_overlay',
  );

  bool get isSupported => Platform.isAndroid;

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
  }) async {
    if (!isSupported) return;
    final payload = jsonEncode({
      'connected': connected,
      'users': users.map(_encodeUser).toList(),
    });
    await _channel.invokeMethod<void>('updateOverlay', {'payload': payload});
  }

  static Map<String, dynamic> _encodeUser(EnhancedNodeInfo node) {
    final ip = node.hasValidIpv4
        ? node.ipv4.split('/').first.trim()
        : '未分配 IP';
    final map = <String, dynamic>{
      'name': node.displayName,
      'ip': ip,
      'latencyMs': node.baseInfo.latencyMs,
    };
    final avatar = node.avatar;
    if (avatar != null && avatar.isNotEmpty) {
      map['avatarBase64'] = base64Encode(avatar);
    }
    return map;
  }

  /// 按设置开关与悬浮窗权限应用显示/隐藏并刷新数据。
  Future<void> applyFromAppState() async {
    if (!isSupported) return;
    final enabled = getIt<AppSettingsService>().isFloatingOverlayEnabled();
    if (!enabled) {
      await hide();
      return;
    }
    if (!await canDrawOverlays()) {
      await hide();
      return;
    }

    final nodes = getIt<NodeManagementService>();
    final connected = nodes.isRunning;
    final users = nodes.userNodes.value
        .where((n) => !n.hostname.startsWith(AppConstants.publicServerHostname))
        .toList();

    await show();
    await updatePayload(connected: connected, users: users);
  }
}
