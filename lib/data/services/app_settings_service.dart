import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/speed_test_snapshot.dart';
import 'package:astral_game/utils/avatar_hash.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsService {
  AppSettingsService(this._prefs, {Directory? supportDir})
    : _supportDir = supportDir;
  // 用户信息
  static const String _keyUsername = 'username';
  static const String _keyAvatarHash = 'avatar_hash';
  static const String _avatarFileName = 'avatar.bin';

  // 通用设置
  static const String _keyCloseMinimize = 'close_minimize';
  static const String _keyAppThemeIndex = 'app_theme_index';

  static const String _keyIsDhcp = 'is_dhcp';
  static const String _keyIsDhcpv6 = 'is_dhcpv6';
  static const String _keyVirtualIp = 'virtual_ip';
  static const String _keyVirtualIpv6 = 'virtual_ipv6';

  final SharedPreferences _prefs;
  final Directory? _supportDir;

  Uint8List? _avatarBytes;
  String? _avatarHash;
  bool _avatarLoaded = false;

  String? _systemUsernameCache;

  File? get _avatarFile {
    final dir = _supportDir;
    if (dir == null) return null;
    return File(p.join(dir.path, _avatarFileName));
  }

  /// 从文件加载头像。
  Future<void> warmUpAvatar() async {
    if (_avatarLoaded) return;
    try {
      final file = _avatarFile;
      if (file != null && file.existsSync()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _avatarBytes = Uint8List.fromList(bytes);
          _avatarHash =
              _prefs.getString(_keyAvatarHash) ??
              avatarContentHash(_avatarBytes);
          if (_avatarHash != null &&
              _prefs.getString(_keyAvatarHash) != _avatarHash) {
            await _prefs.setString(_keyAvatarHash, _avatarHash!);
          }
          return;
        }
      }
      _avatarBytes = null;
      _avatarHash = _prefs.getString(_keyAvatarHash);
    } catch (e) {
      appLogger.e('[AppSettingsService] 加载头像失败: $e');
    } finally {
      _avatarLoaded = true;
    }
  }

  // ---- 主题/外观 ----

  /// 定制主题索引（[AppThemeId.storageIndex]）。
  int getAppThemeIndex() => _prefs.getInt(_keyAppThemeIndex) ?? 0;

  Future<void> setAppThemeIndex(int index) async =>
      await _prefs.setInt(_keyAppThemeIndex, index);

  // ---- 网络配置 ----

  static const String _keyDisableP2p = 'disable_p2p';
  static const String _keyFloatingOverlayEnabled = 'floating_overlay_enabled';
  static const String _keyMemberListCompact = 'member_list_compact';

  bool isDisableP2p() => _prefs.getBool(_keyDisableP2p) ?? false;
  Future<void> setDisableP2p(bool value) async =>
      await _prefs.setBool(_keyDisableP2p, value);

  /// Android：房间在线用户悬浮窗。
  bool isFloatingOverlayEnabled() =>
      _prefs.getBool(_keyFloatingOverlayEnabled) ?? false;

  Future<void> setFloatingOverlayEnabled(bool value) async =>
      await _prefs.setBool(_keyFloatingOverlayEnabled, value);

  /// 房间成员列表：简洁模式（仅显示 IP / 延迟）。
  bool isMemberListCompact() => _prefs.getBool(_keyMemberListCompact) ?? false;

  Future<void> setMemberListCompact(bool value) async =>
      await _prefs.setBool(_keyMemberListCompact, value);

  static const String _keyCustomVpnRoutes = 'custom_vpn_routes';

  /// Android VpnService 额外路由（CIDR 列表）。
  List<String> getCustomVpnRoutes() =>
      _prefs.getStringList(_keyCustomVpnRoutes) ?? const [];

  Future<void> setCustomVpnRoutes(List<String> routes) async =>
      await _prefs.setStringList(_keyCustomVpnRoutes, routes);

  // ---- 用户信息 ----

  static const String _keyProfileSetupDone = 'profile_setup_done';

  /// 是否需要首次启动资料引导：从未设置昵称，且未完成/跳过引导。
  bool needsProfileSetup() {
    final savedUsername = _prefs.getString(_keyUsername);
    if (savedUsername != null && savedUsername.isNotEmpty) return false;
    return !(_prefs.getBool(_keyProfileSetupDone) ?? false);
  }

  /// 标记首次启动资料引导已完成（保存或跳过）。
  Future<void> markProfileSetupDone() async =>
      await _prefs.setBool(_keyProfileSetupDone, true);

  /// 获取用户名，未设置时默认使用系统用户名
  String getUsername() {
    final savedUsername = _prefs.getString(_keyUsername);
    if (savedUsername != null && savedUsername.isNotEmpty) {
      return savedUsername;
    }
    return _systemUsernameCache ?? _fallbackUsername();
  }

  /// 启动时预取系统登录用户名，之后 [getUsername] 同步读取缓存。
  ///
  /// Windows 由 device_info_plus 调用原生 `GetUserNameW` 获取；
  /// macOS / Linux 没有统一的库接口，读取 POSIX 登录名环境变量；
  /// Android / iOS 没有登录用户概念，回退为「玩家」。
  Future<void> warmUpSystemUsername() async {
    if (_systemUsernameCache != null) return;
    try {
      if (Platform.isWindows) {
        final info = await DeviceInfoPlugin().windowsInfo;
        _systemUsernameCache = _normalizeUsername(info.userName);
      } else if (Platform.isMacOS || Platform.isLinux) {
        _systemUsernameCache = _normalizeUsername(
          Platform.environment['USER'] ?? Platform.environment['LOGNAME'],
        );
      }
    } catch (e) {
      appLogger.e('[AppSettingsService] 读取系统用户名失败: $e');
    }
  }

  String? _normalizeUsername(String? name) {
    final trimmed = name?.trim();
    return trimmed != null && trimmed.isNotEmpty ? trimmed : null;
  }

  /// 预取失败时的兜底，取不到时回退为「玩家」
  String _fallbackUsername() {
    if (!Platform.isWindows) {
      final posixName = _normalizeUsername(
        Platform.environment['USER'] ?? Platform.environment['LOGNAME'],
      );
      if (posixName != null) return posixName;
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

  /// 写入文件 + hash。
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
  }

  /// 清除头像
  Future<void> clearAvatar() async {
    _avatarBytes = null;
    _avatarHash = null;
    _avatarLoaded = true;
    final file = _avatarFile;
    if (file != null && file.existsSync()) {
      await file.delete();
    }
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

  /// 是否使用 DHCPv6 自动分配虚拟 IPv6（EasyTier `dhcpv6`）
  bool getIsDhcpv6() => _prefs.getBool(_keyIsDhcpv6) ?? true;
  Future<void> setIsDhcpv6(bool value) async =>
      await _prefs.setBool(_keyIsDhcpv6, value);

  /// 获取虚拟 IP（未设置时为空，由用户手动填写并记忆）
  String getVirtualIp() => _prefs.getString(_keyVirtualIp) ?? '';
  Future<void> setVirtualIp(String value) async =>
      await _prefs.setString(_keyVirtualIp, value);

  /// 获取虚拟 IPv6（未设置时为空，由用户手动填写并记忆）
  String getVirtualIpv6() => _prefs.getString(_keyVirtualIpv6) ?? '';
  Future<void> setVirtualIpv6(String value) async =>
      await _prefs.setString(_keyVirtualIpv6, value);

  // ---- 更新 ----

  static const String _keyUpdateAutoCheck = 'update_auto_check';
  static const String _keyUpdateBetaChannel = 'update_beta_channel';

  /// 启动时是否自动检查更新。
  bool getUpdateAutoCheck() => _prefs.getBool(_keyUpdateAutoCheck) ?? true;
  Future<void> setUpdateAutoCheck(bool value) async =>
      await _prefs.setBool(_keyUpdateAutoCheck, value);

  /// 是否加入测试版（预发布）频道。
  bool getUpdateBetaChannel() => _prefs.getBool(_keyUpdateBetaChannel) ?? false;
  Future<void> setUpdateBetaChannel(bool value) async =>
      await _prefs.setBool(_keyUpdateBetaChannel, value);

  // ---- Windows 启动行为 ----

  static const String _keyStartToTray = 'start_to_tray';
  static const String _keyAutoEnterRoom = 'auto_enter_room';
  static const String _keyAutoEnterBookmarkId = 'auto_enter_bookmark_id';
  static const String _keyLastRoomPayload = 'last_room_payload';

  /// 开机启动后是否直接驻留托盘（仅开机拉起时生效）。
  bool getStartToTray() => _prefs.getBool(_keyStartToTray) ?? false;
  Future<void> setStartToTray(bool value) async =>
      await _prefs.setBool(_keyStartToTray, value);

  /// 启动后是否自动进入指定房间（房间来自收藏）。
  bool getAutoEnterRoom() => _prefs.getBool(_keyAutoEnterRoom) ?? false;
  Future<void> setAutoEnterRoom(bool value) async =>
      await _prefs.setBool(_keyAutoEnterRoom, value);

  /// 启动后自动进入的收藏房间 id（收藏被删除时为空）。
  int? getAutoEnterBookmarkId() => _prefs.getInt(_keyAutoEnterBookmarkId);
  Future<void> setAutoEnterBookmarkId(int? id) async {
    if (id == null) {
      await _prefs.remove(_keyAutoEnterBookmarkId);
      return;
    }
    await _prefs.setInt(_keyAutoEnterBookmarkId, id);
  }

  /// 上次成功进入的房间（离开房间时清除）。
  RoomInvitePayload? getLastRoomPayload() {
    final raw = _prefs.getString(_keyLastRoomPayload);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return RoomInvitePayload.fromJson(json);
    } catch (e) {
      appLogger.w('[AppSettingsService] 解析上次房间失败: $e');
      return null;
    }
  }

  Future<void> setLastRoomPayload(RoomInvitePayload? payload) async {
    if (payload == null) {
      await _prefs.remove(_keyLastRoomPayload);
      return;
    }
    await _prefs.setString(_keyLastRoomPayload, jsonEncode(payload.toJson()));
  }

  // ---- 测速 ----

  static const String _keySpeedTestSnapshot = 'speed_test_snapshot';

  SpeedTestSnapshot? getSpeedTestSnapshot() =>
      SpeedTestSnapshot.tryParse(_prefs.getString(_keySpeedTestSnapshot));

  Future<void> setSpeedTestSnapshot(SpeedTestSnapshot snapshot) async =>
      await _prefs.setString(
        _keySpeedTestSnapshot,
        jsonEncode(snapshot.toJson()),
      );
}
