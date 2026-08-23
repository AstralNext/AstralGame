/// 对端链路时延 / 丢包。与成员身份拆开，避免 1ms 抖动触发整表重建。
class PeerLinkMetrics {
  const PeerLinkMetrics({
    required this.latencyMs,
    required this.lossRate,
  });

  static const zero = PeerLinkMetrics(latencyMs: 0, lossRate: 0);

  /// 时延变化小于该值（毫秒）时不通知 UI。
  static const hysteresisMs = 8.0;

  final double latencyMs;
  final double lossRate;

  bool visiblyDiffersFrom(PeerLinkMetrics other) {
    return (latencyMs - other.latencyMs).abs() >= hysteresisMs ||
        (lossRate * 10).round() != (other.lossRate * 10).round();
  }
}
