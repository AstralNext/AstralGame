import 'dart:io' show Platform;

/// 原生端使用 [`Platform`]（windows / macos / linux / android / ios …）。
class RuntimePlatform {
  RuntimePlatform._();

  /// 与 [`Platform.operatingSystem`] 一致的小写标识，例如 `windows`、`android`。
  static String get operatingSystem => Platform.operatingSystem;

  /// 系统版本字符串（[`dart:io`] 原始值）。完整展示请用 [`ClientRuntimeInfo`] 在
  /// [`warmUp`] 后提供的 [`operatingSystemVersion`]（[`device_info_plus`]）。
  static String get operatingSystemVersion => Platform.operatingSystemVersion;
}
