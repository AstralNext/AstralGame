/// Web 端无 `dart:io`，占位。
class RuntimePlatform {
  RuntimePlatform._();

  static String get operatingSystem => 'web';

  static String get operatingSystemVersion => '';

  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isFuchsia => false;
  static bool get isMobile => false;
  static bool get isDesktop => false;
  static bool get isApple => false;
}
