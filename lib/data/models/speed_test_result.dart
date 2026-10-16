class SpeedTestResult {
  const SpeedTestResult({
    this.latencyMs,
    this.downloadLatencyMs,
    this.uploadLatencyMs,
    this.downloadMbps,
    this.uploadMbps,
    this.error,
  });

  const SpeedTestResult.failure(String message) : this(error: message);

  final double? latencyMs;

  final double? downloadLatencyMs;

  final double? uploadLatencyMs;

  final double? downloadMbps;

  final double? uploadMbps;

  final String? error;

  bool get ok => error == null;
}
