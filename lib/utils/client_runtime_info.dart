import 'package:package_info_plus/package_info_plus.dart';

import 'client_os_detail.dart';
import 'runtime_platform.dart';

/// 本机客户端环境：操作系统、`package_info` 应用版本等。
///
/// 在 [`setupDI`] 里调用 [`warmUp`] 一次后再应答 RPC，避免首次 `user.getInfo` 拿不到版本号。
class ClientRuntimeInfo {
  ClientRuntimeInfo._();

  static bool _ready = false;
  static String _appVersion = '';
  static String _appName = '';
  static String _operatingSystemVersionDetail = '';

  static Future<void> warmUp() async {
    if (_ready) return;
    try {
      final p = await PackageInfo.fromPlatform();
      _appName = p.appName;
      final ver = p.version.trim();
      final build = p.buildNumber.trim();
      _appVersion =
          build.isEmpty ? ver : (ver.isEmpty ? build : '$ver+$build');
    } catch (_) {
      _appVersion = '';
      _appName = '';
    }

    try {
      final detail = await loadDetailedOperatingSystemVersion();
      _operatingSystemVersionDetail = detail.trim();
    } catch (_) {
      _operatingSystemVersionDetail = '';
    }

    _ready = true;
  }

  /// 应用显示名（来自包配置）。
  static String get appName => _appName.isEmpty ? 'astral_game' : _appName;

  /// 应用版本，形如 `1.0.0` 或 `1.0.0+1`。
  static String get appVersion =>
      _appVersion.isEmpty ? 'unknown' : _appVersion;

  /// `windows` / `android` / `macos` / `linux` / `ios` / `web` 等。
  static String get operatingSystem => RuntimePlatform.operatingSystem;

  /// 操作系统版本字符串（[`device_info_plus`] / Web 浏览器信息；失败则回退 [`RuntimePlatform`]）。
  static String get operatingSystemVersion =>
      _operatingSystemVersionDetail.isNotEmpty
          ? _operatingSystemVersionDetail
          : RuntimePlatform.operatingSystemVersion;
}
