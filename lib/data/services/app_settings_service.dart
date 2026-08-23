import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/utils/avatar_hash.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService {
  // 用户信息
  static const String _keyUsername = 'username';
  /// 旧版：整图 Base64。迁移后删除。
  static const String _keyAvatar = 'avatar';
  static const String _keyAvatarHash = 'avatar_hash';
  static const String _avatarFileName = 'avatar.bin';

  // 通用设置
  static const String _keyCloseMinimize = 'close_minimize';
  static const String _keyAppThemeIndex = 'app_theme_index';
  static const String _keyAppThemeSchema = 'app_theme_schema';
  static const int appThemeSchemaCurrent = 2;

  static const String _keyIsDhcp = 'is_dhcp';
  static const String _keyVirtualIp = 'virtual_ip';

  AppSettingsService(this._prefs, {Directory? supportDir})
      : _supportDir = supportDir;

  final SharedPreferences _prefs;
  final Directory? _supportDir;

  Uint8List? _avatarBytes;
  String? _avatarHash;
  bool _avatarLoaded = false;

  File? get _avatarFile {
    final dir = _supportDir;
    if (dir == null) return null;
    return File(p.join(dir.path, _avatarFileName));
  }

  /// 从文件加载头像；若只有旧版 prefs Base64 则迁移并删掉。
  Future<void> warmUpAvatar() async {
    if (_avatarLoaded) return;
    try {
      final file = _avatarFile;
      if (file != null && await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _avatarBytes = Uint8List.fromList(bytes);
          _avatarHash = _prefs.getString(_keyAvatarHash) ??
              avatarContentHash(_avatarBytes);
          if (_avatarHash != null &&
              _prefs.getString(_keyAvatarHash) != _avatarHash) {
            await _prefs.setString(_keyAvatarHash, _avatarHash!);
          }
          await _prefs.remove(_keyAvatar);
          return;
        }
      }
      await _migrateLegacyPrefsAvatar();
    } catch (e) {
      appLogger.e('[AppSettingsService] 加载头像失败: $e');
    } finally {
      _avatarLoaded = true;
    }
  }

  Future<void> _migrateLegacyPrefsAvatar() async {
    final avatarBase64 = _prefs.getString(_keyAvatar);
    if (avatarBase64 == null || avatarBase64.isEmpty) {
      _avatarBytes = null;
      _avatarHash = _prefs.getString(_keyAvatarHash);
      return;
    }
    try {
      final bytes = Uint8List.fromList(base64Decode(avatarBase64));
      await setAvatar(bytes);
    } catch (e) {
      appLogger.e('[AppSettingsService] 迁移旧头像失败: $e');
      await _prefs.remove(_keyAvatar);
      _avatarBytes = null;
      _avatarHash = null;
    }
  }

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

  static const String _keyCustomVpnRoutes = 'custom_vpn_routes';

  /// Android VpnService 额外路由（CIDR 列表）。
  List<String> getCustomVpnRoutes() =>
      _prefs.getStringList(_keyCustomVpnRoutes) ?? const [];

  Future<void> setCustomVpnRoutes(List<String> routes) async =>
      await _prefs.setStringList(_keyCustomVpnRoutes, routes);

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

  /// 内存中的头像字节；启动时先 [warmUpAvatar]。
  Uint8List? getAvatar() => _avatarBytes;

  /// 头像内容 hash；无头像为空。
  String? getAvatarHash() => _avatarHash ?? avatarContentHash(_avatarBytes);

  /// 写入文件 + hash；不再把整图放进 SharedPreferences。
  Future<void> setAvatar(Uint8List avatar) async {
    _avatarBytes = avatar;
    _avatarHash = avatarContentHash(avatar);
    _avatarLoaded = true;
    final file = _avatarFile;
    if (file != null) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(avatar, flush: true);
    }
    if (_avatarHash != null) {
      await _prefs.setString(_keyAvatarHash, _avatarHash!);
    }
    await _prefs.remove(_keyAvatar);
  }

  /// 清除头像
  Future<void> clearAvatar() async {
    _avatarBytes = null;
    _avatarHash = null;
    _avatarLoaded = true;
    final file = _avatarFile;
    if (file != null && await file.exists()) {
      await file.delete();
    }
    await _prefs.remove(_keyAvatar);
    await _prefs.remove(_keyAvatarHash);
  }

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
