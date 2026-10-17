class SpeedTestResult {
  const SpeedTestResult({
    this.latencyMs,
    this.downloadLatencyMs,
    this.uploadLatencyMs,
    this.downloadMbps,
    this.uploadMbps,
    this.lossRate,
    this.error,
  });

  const SpeedTestResult.failure(String message) : this(error: message);

  final double? latencyMs;

  final double? downloadLatencyMs;

  final double? uploadLatencyMs;

  final double? downloadMbps;

  final double? uploadMbps;

  /// 丢包率（百分比 0–100），基于测速期间 TCP 探测失败比例估算。
  final double? lossRate;

  final String? error;

  bool get ok => error == null;
}
