import 'package:flutter/material.dart';

/// 在线列表中展示的 Windows 专用网络防火墙状态（RPC `firewall` 字段）。
class FirewallPresentation {
  const FirewallPresentation({
    required this.shortLabel,
    required this.icon,
    this.isEnabled,
  });

  final String shortLabel;
  final IconData icon;

  /// `null` 表示非 Windows 或未知。
  final bool? isEnabled;

  factory FirewallPresentation.fromWire(String? raw) {
    switch (raw) {
      case 'enabled':
        return const FirewallPresentation(
          shortLabel: '防火墙开',
          icon: Icons.shield,
          isEnabled: true,
        );
      case 'disabled':
        return const FirewallPresentation(
          shortLabel: '防火墙关',
          icon: Icons.shield_outlined,
          isEnabled: false,
        );
      case 'unsupported':
      default:
        return const FirewallPresentation(
          shortLabel: '',
          icon: Icons.shield_outlined,
          isEnabled: null,
        );
    }
  }

  bool get hasLabel => shortLabel.isNotEmpty;
}
