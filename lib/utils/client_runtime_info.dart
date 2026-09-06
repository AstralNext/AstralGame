import 'package:astral_game/utils/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'client_os_detail.dart';
import 'runtime_platform.dart';

/// RPC `user.getInfo` 环境字段 → 节点 metadata 字段的固定映射。
///
/// 环境字段的生产（[`ClientRuntimeInfo.envSnapshot`]）、本机节点组装、
/// 远端响应解析三处共用此映射；新增环境字段只需在此登记一行。
const Map<String, String> kPeerEnvRpcToMetaKey = {
  'os': 'peerOs',
  'osVersion': 'peerOsVersion',
  'appName': 'peerAppName',
  'appVersion': 'peerAppVersion',
  'network': 'peerNetwork',
  'firewall': 'peerFirewall',
  'isp': 'peerIsp',
};

/// 本机客户端环境：操作系统、`package_info` 应用版本等。
///
/// 在 [`setupDI`] 里调用 [`warmUp`] 一次后再应答 RPC，避免首次 `user.getInfo` 拿不到版本号。
class ClientRuntimeInfo {
  ClientRuntimeInfo._();

  static bool _ready = false;
  static String _appVersion = '';
  static String _appName = '';
  static String _packageName = '';
  static String _operatingSystemVersionDetail = '';

  static Future<void> warmUp() async {
    if (_ready) return;
    try {
      final p = await PackageInfo.fromPlatform();
      _appName = p.appName;
      _packageName = p.packageName.trim();
      _appVersion = resolveAppVersion(
        version: p.version,
        buildNumber: p.buildNumber,
      );
    } catch (e) {
      appLogger.w('[ClientRuntimeInfo] 操作失败', error: e);
      _appVersion = '';
      _appName = '';
      _packageName = '';
    }

    try {
      final detail = await loadDetailedOperatingSystemVersion();
      _operatingSystemVersionDetail = detail.trim();
    } catch (e) {
      appLogger.w('[ClientRuntimeInfo] 操作失败', error: e);
      _operatingSystemVersionDetail = '';
    }

    _ready = true;
  }

  /// 应用显示名（来自包配置）。
  static String get appName => _appName.isEmpty ? 'astral_game' : _appName;

  /// Android `applicationId` / 其它平台包名；未就绪时为空。
  static String get packageName => _packageName;

  /// 应用版本（pubspec `versionName`，如 `1.0.41`）。
  ///
  /// 不要把 Android `versionCode` 拼成 `1.0.41+1`：未写 `+build` 时
  /// Flutter 仍会把 versionCode 默认成 1。
  static String get appVersion => _appVersion.isEmpty ? 'unknown' : _appVersion;

  /// 展示/上报用版本：只用 versionName；buildNumber 仅在 version 为空时回退。
  static String resolveAppVersion({
    required String version,
    required String buildNumber,
  }) {
    final ver = version.trim();
    if (ver.isNotEmpty) return ver;
    return buildNumber.trim();
  }

  /// `windows` / `android` / `macos` / `linux` / `ios` / `web` 等。
  static String get operatingSystem => RuntimePlatform.operatingSystem;

  /// 操作系统版本字符串（[`device_info_plus`] / Web 浏览器信息；失败则回退 [`RuntimePlatform`]）。
  static String get operatingSystemVersion =>
      _operatingSystemVersionDetail.isNotEmpty
      ? _operatingSystemVersionDetail
      : RuntimePlatform.operatingSystemVersion;

  /// 本机环境快照（RPC `user.getInfo` 字段命名，见 [`kPeerEnvRpcToMetaKey`]）。
  ///
  /// os/osVersion/appName/appVersion 来自本机；network/firewall/isp 是动态
  /// 数据，由调用方获取后传入。空值字段由消费方按需过滤。
  static Map<String, dynamic> envSnapshot({
    String? networkWire,
    required String firewallWire,
    String? isp,
  }) => {
    'os': operatingSystem,
    'osVersion': operatingSystemVersion,
    'appName': appName,
    'appVersion': appVersion,
    'network': networkWire,
    'firewall': firewallWire,
    'isp': isp,
  };
}
