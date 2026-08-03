import 'package:device_info_plus/device_info_plus.dart';

Future<String> loadDetailedOperatingSystemVersion() async {
  try {
    final w = await DeviceInfoPlugin().webBrowserInfo;
    final name = w.browserName.name;
    final ver = (w.appVersion ?? '').trim();
    if (ver.isEmpty) return name;
    return '$name $ver';
  } catch (_) {
    return '';
  }
}
