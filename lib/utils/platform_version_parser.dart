import 'package:flutter/material.dart';

class PlatformVersionParser {
  static (String, IconData) parsePlatformInfo(String versionString) {
    final parts = versionString.split('|');

    if (parts.length < 2) {
      return ('', Icons.memory);
    }

    final platform = parts[1].trim().toLowerCase();

    if (platform.contains('windows')) {
      return ('Windows', Icons.window);
    } else if (platform.contains('linux')) {
      return ('Linux', Icons.terminal);
    } else if (platform.contains('android')) {
      return ('Android', Icons.android);
    } else if (platform.contains('macos') || platform.contains('mac')) {
      return ('macOS', Icons.apple);
    } else if (platform.contains('ios')) {
      return ('iOS', Icons.phone_iphone);
    } else {
      return (parts[1].trim(), Icons.devices);
    }
  }

  static String getVersionNumber(String versionString) {
    return versionString.split('|')[0].trim();
  }

}