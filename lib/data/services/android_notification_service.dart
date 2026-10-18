import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/services.dart';

/// Android 通知栏：前台服务通知权限与 VPN 通知样式。
class AndroidNotificationService {
  static const _channel = MethodChannel('fan.astral.next.game/notifications');

  bool get isSupported => RuntimePlatform.isAndroid;

  /// 确保 Android 13+ 通知权限；未授予时弹出系统授权框。
  Future<bool> ensurePermission() async {
    if (!isSupported) return true;
    try {
      final granted = await _channel.invokeMethod<bool>(
        'ensureNotificationPermission',
      );
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 用本地化文案和点击跳转覆盖 VPN 前台服务通知。
  Future<void> refreshVpnNotification() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('refreshVpnNotification');
    } catch (_) {}
  }

  Future<void> cancelVpnNotification() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('cancelVpnNotification');
    } catch (_) {}
  }
}
