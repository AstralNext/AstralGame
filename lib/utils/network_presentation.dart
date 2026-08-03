import 'package:flutter/material.dart';

import 'package:astral_game/data/services/connectivity_status_service.dart';

/// 在线列表中展示的「网络承载」短标签 + Material 图标。
class NetworkPresentation {
  const NetworkPresentation({
    required this.kind,
    required this.shortLabel,
    required this.icon,
  });

  final NetworkKind kind;
  final String shortLabel;
  final IconData icon;

  factory NetworkPresentation.forKind(NetworkKind kind) {
    switch (kind) {
      case NetworkKind.wifi:
        return const NetworkPresentation(
          kind: NetworkKind.wifi,
          shortLabel: 'Wi-Fi',
          icon: Icons.wifi,
        );
      case NetworkKind.ethernet:
        return const NetworkPresentation(
          kind: NetworkKind.ethernet,
          shortLabel: '有线',
          icon: Icons.settings_ethernet,
        );
      case NetworkKind.mobile:
        return const NetworkPresentation(
          kind: NetworkKind.mobile,
          shortLabel: '蜂窝',
          icon: Icons.signal_cellular_alt,
        );
      case NetworkKind.bluetooth:
        return const NetworkPresentation(
          kind: NetworkKind.bluetooth,
          shortLabel: '蓝牙',
          icon: Icons.bluetooth,
        );
      case NetworkKind.satellite:
        return const NetworkPresentation(
          kind: NetworkKind.satellite,
          shortLabel: '卫星',
          icon: Icons.satellite_alt,
        );
      case NetworkKind.none:
        return const NetworkPresentation(
          kind: NetworkKind.none,
          shortLabel: '离线',
          icon: Icons.signal_wifi_off,
        );
      case NetworkKind.other:
        return const NetworkPresentation(
          kind: NetworkKind.other,
          shortLabel: '其他',
          icon: Icons.network_check,
        );
      case NetworkKind.unknown:
        return const NetworkPresentation(
          kind: NetworkKind.unknown,
          shortLabel: '',
          icon: Icons.network_check,
        );
    }
  }

  factory NetworkPresentation.fromWire(String? raw) =>
      NetworkPresentation.forKind(NetworkKindWire.fromWire(raw));

  bool get hasLabel => shortLabel.isNotEmpty;
}
