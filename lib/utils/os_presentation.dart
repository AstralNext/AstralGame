import 'package:flutter/material.dart';

import 'package:astral_game/data/models/enhanced_node_info.dart';

/// 在线列表等处展示的「系统」短标签 + Material 图标。
class OsPresentation {
  /// 优先 [`EnhancedNodeInfo.peerOs`]（RPC `user.getInfo`），否则解析 EasyTier `version` 管道串。
  factory OsPresentation.forNode(EnhancedNodeInfo node) {
    final key = node.peerOs?.trim().toLowerCase();
    if (key != null && key.isNotEmpty) {
      return OsPresentation(
        shortLabel: humanizeOsKey(key),
        icon: iconForOsKey(key),
      );
    }
    final pipe = node.baseInfo.version.split('|');
    if (pipe.length >= 2) {
      final plat = pipe[1].trim().toLowerCase();
      if (plat.isNotEmpty) {
        return OsPresentation(
          shortLabel: humanizeOsKey(plat),
          icon: iconForOsKey(plat),
        );
      }
    }
    return const OsPresentation(shortLabel: '', icon: Icons.devices_outlined);
  }
  const OsPresentation({required this.shortLabel, required this.icon});

  final String shortLabel;
  final IconData icon;

  /// 将 OS key（如 `windows`/`macos`）转为展示名；未知值原样返回（超长截断）。
  static String humanizeOsKey(String key) {
    final k = key.toLowerCase();
    if (k.contains('windows')) return 'Windows';
    if (k.contains('android')) return 'Android';
    if (k.contains('ios')) return 'iOS';
    if (k.contains('mac')) return 'macOS';
    if (k.contains('linux')) return 'Linux';
    if (k.contains('web')) return 'Web';
    return key.length <= 16 ? key : '${key.substring(0, 13)}…';
  }

  static IconData iconForOsKey(String key) {
    final k = key.toLowerCase();
    if (k.contains('windows')) return Icons.window;
    if (k.contains('android')) return Icons.android;
    if (k.contains('ios')) return Icons.phone_iphone;
    if (k.contains('mac')) return Icons.apple;
    if (k.contains('linux')) return Icons.terminal;
    if (k.contains('web')) return Icons.language;
    return Icons.devices_outlined;
  }
}
