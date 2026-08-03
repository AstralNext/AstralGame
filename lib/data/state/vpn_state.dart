import 'package:signals/signals.dart';

/// VPN 相关状态
class VpnState {
  /// VPN 是否正在运行
  final isRunning = signal(false);

  /// VPN 是否正在连接中
  final isConnecting = signal(false);

  /// VPN IPv4 地址
  final ipv4Addr = signal('10.126.126.1/24');

  /// VPN MTU
  final mtu = signal(1500);

  /// 自定义 VPN 路由
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
    customRoutes.value = value;
  }
}
