/// Web 端无 `dart:io`，占位。
class RuntimePlatform {
  RuntimePlatform._();

  static String get operatingSystem => 'web';

  static String get operatingSystemVersion => '';
}
