import 'dart:convert';
import 'dart:typed_data';
import 'package:astral_game/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService {
  // 用户信息
  static const String _keyUsername = 'username';
  static const String _keyAvatar = 'avatar';

  // 通用设置
  static const String _keyCloseMinimize = 'close_minimize';
  static const String _keyAppThemeIndex = 'app_theme_index';
  static const String _keyAppThemeSchema = 'app_theme_schema';
  static const int appThemeSchemaCurrent = 2;

  static const String _keyIsDhcp = 'is_dhcp';
  static const String _keyVirtualIp = 'virtual_ip';

  final SharedPreferences _prefs;

  AppSettingsService(this._prefs);

  // ---- 主题/外观 ----

  /// 定制主题索引（[AppThemeId.storageIndex]）。
  int getAppThemeIndex() => _prefs.getInt(_keyAppThemeIndex) ?? 0;

  Future<void> setAppThemeIndex(int index) async =>
      await _prefs.setInt(_keyAppThemeIndex, index);

  /// 主题偏好 schema 版本（当前为 [appThemeSchemaCurrent]）。
  int getAppThemeSchema() => _prefs.getInt(_keyAppThemeSchema) ?? 1;

  Future<void> setAppThemeSchema(int schema) async =>
      await _prefs.setInt(_keyAppThemeSchema, schema);

  // ---- 网络配置 ----

  static const String _keyDisableP2p = 'disable_p2p';
  static const String _keyEnableUdpBroadcastRelay = 'enable_udp_broadcast_relay';
  static const String _keyFloatingOverlayEnabled = 'floating_overlay_enabled';

  bool isDisableP2p() => _prefs.getBool(_keyDisableP2p) ?? false;
  Future<void> setDisableP2p(bool value) async =>
      await _prefs.setBool(_keyDisableP2p, value);

  /// Windows：是否启用 EasyTier「UDP 广播转发到虚拟网」。
  bool isEnableUdpBroadcastRelay() =>
      _prefs.getBool(_keyEnableUdpBroadcastRelay) ?? false;
  Future<void> setEnableUdpBroadcastRelay(bool value) async =>
      await _prefs.setBool(_keyEnableUdpBroadcastRelay, value);

  /// Android：房间在线用户悬浮窗。
  bool isFloatingOverlayEnabled() =>
      _prefs.getBool(_keyFloatingOverlayEnabled) ?? false;

  Future<void> setFloatingOverlayEnabled(bool value) async =>
      await _prefs.setBool(_keyFloatingOverlayEnabled, value);

  // ---- 用户信息 ----

  /// 获取用户名，如果为空则返回系统用户名
  String getUsername() {
    final savedUsername = _prefs.getString(_keyUsername);
    if (savedUsername != null && savedUsername.isNotEmpty) {
      return savedUsername;
    }
    return '玩家';
  }

  /// 设置用户名
  Future<void> setUsername(String username) async =>
      await _prefs.setString(_keyUsername, username);

  /// 获取头像数据（Base64 编码）
  Uint8List? getAvatar() {
    final avatarBase64 = _prefs.getString(_keyAvatar);
    if (avatarBase64 == null || avatarBase64.isEmpty) {
      return null;
    }
     try {
      return base64Decode(avatarBase64);
    } catch (e) {
      appLogger.e('[AppSettingsService] Failed to decode avatar: $e');
      return null;
    }
  }

  /// 设置头像数据
  Future<void> setAvatar(Uint8List avatar) async {
    final avatarBase64 = base64Encode(avatar);
    await _prefs.setString(_keyAvatar, avatarBase64);
  }

  /// 清除头像
  Future<void> clearAvatar() async =>
      await _prefs.remove(_keyAvatar);

  // ---- 通用设置 ----

  /// 获取关闭时最小化设置
  bool getCloseMinimize() => _prefs.getBool(_keyCloseMinimize) ?? true;
  Future<void> setCloseMinimize(bool value) async =>
      await _prefs.setBool(_keyCloseMinimize, value);

  /// 是否使用 DHCP 分配虚拟 IP
  bool getIsDhcp() => _prefs.getBool(_keyIsDhcp) ?? true;
  Future<void> setIsDhcp(bool value) async =>
      await _prefs.setBool(_keyIsDhcp, value);

  /// 获取虚拟 IP
  String getVirtualIp() => _prefs.getString(_keyVirtualIp) ?? '10.147.18.24';
  Future<void> setVirtualIp(String value) async =>
      await _prefs.setString(_keyVirtualIp, value);
}
