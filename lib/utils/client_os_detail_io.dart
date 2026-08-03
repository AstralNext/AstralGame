import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

Future<String> loadDetailedOperatingSystemVersion() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (Platform.isWindows) {
      final w = await plugin.windowsInfo;
      return _formatWindows(w);
    }
    if (Platform.isAndroid) {
      final a = await plugin.androidInfo;
      return 'Android ${a.version.release} (SDK ${a.version.sdkInt}) · ${a.model}';
    }
    if (Platform.isIOS) {
      final i = await plugin.iosInfo;
      return '${i.systemName} ${i.systemVersion} · ${i.model}';
    }
    if (Platform.isMacOS) {
      final m = await plugin.macOsInfo;
      return 'macOS ${m.osRelease} (${m.majorVersion}.${m.minorVersion}.${m.patchVersion})';
    }
    if (Platform.isLinux) {
      final l = await plugin.linuxInfo;
      final name = l.prettyName.trim();
      return name.isNotEmpty ? name : Platform.operatingSystemVersion;
    }
    return Platform.operatingSystemVersion;
  } catch (_) {
    return Platform.operatingSystemVersion;
  }
}

/// [WindowsDeviceInfo.productName] 仍可能含「Windows 10」，但 [WindowsDeviceInfo.buildNumber]
/// ≥ 22000 时为 Windows 11（微软未改注册表 ProductName 的常见情况）。以插件提供的 build 为准修正展示名。
String _formatWindows(WindowsDeviceInfo w) {
  var product = w.productName.trim();
  if (w.buildNumber >= 22000) {
    product = product.replaceAll(
      RegExp(r'Windows\s*10', caseSensitive: false),
      'Windows 11',
    );
  }
  final dv = w.displayVersion.trim();
  final parts = <String>[product];
  if (dv.isNotEmpty) parts.add(dv);
  parts.add('Build ${w.buildNumber}');
  return parts.join(' · ');
}
