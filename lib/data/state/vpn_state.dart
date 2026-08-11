import 'package:signals/signals.dart';

/// VPN 相关状态（Android VpnService 路由等）。
class VpnState {
  /// VPN 是否正在运行
  final isRunning = signal(false);

  /// VPN 是否正在连接中
  final isConnecting = signal(false);

  /// VPN IPv4 地址
  final ipv4Addr = signal('10.126.126.1/24');

  /// VPN MTU（对齐旧版 Astral 默认 1300）
  final mtu = signal(1300);

  /// 自定义 VPN 路由（CIDR），写入 Android VpnService，不含对端子网代理。
  final customRoutes = signal<List<String>>([]);

  void setRunning(bool value) {
    isRunning.value = value;
  }

  void setConnecting(bool value) {
    isConnecting.value = value;
  }

  void setIpv4Addr(String value) {
    ipv4Addr.value = value;
  }

  void setMtu(int value) {
    mtu.value = value;
  }

  void setCustomRoutes(List<String> value) {
    customRoutes.value = List<String>.unmodifiable(value);
  }

  void addCustomRoute(String cidr) {
    final next = [...customRoutes.value, cidr.trim()];
    customRoutes.value = List<String>.unmodifiable(next);
  }

  void updateCustomRoute(int index, String cidr) {
    if (index < 0 || index >= customRoutes.value.length) return;
    final next = [...customRoutes.value];
    next[index] = cidr.trim();
    customRoutes.value = List<String>.unmodifiable(next);
  }

  void removeCustomRoute(int index) {
    if (index < 0 || index >= customRoutes.value.length) return;
    final next = [...customRoutes.value]..removeAt(index);
    customRoutes.value = List<String>.unmodifiable(next);
  }
}
