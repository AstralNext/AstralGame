/// 某条开放游戏在本机的注入 / 转发状态（供 UI 绿点）。
class LanRelayStatus {
  const LanRelayStatus({
    required this.listingKey,
    required this.localEndpoint,
    required this.remoteEndpoint,
    required this.inject,
    required this.forward,
  });

  final String listingKey;
  final String localEndpoint;
  final String remoteEndpoint;
  final bool inject;
  final bool forward;

  bool get isActive => inject || forward;
}
