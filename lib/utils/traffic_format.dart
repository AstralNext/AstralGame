/// 流量 / 速率展示格式化。
abstract final class TrafficFormat {
  static String bytes(num value) {
    final v = value < 0 ? 0.0 : value.toDouble();
    if (v < 1024) return '${v.toStringAsFixed(0)} B';
    if (v < 1024 * 1024) return '${(v / 1024).toStringAsFixed(1)} KB';
    if (v < 1024 * 1024 * 1024) {
      return '${(v / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(v / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String rate(num bytesPerSecond) => '${bytes(bytesPerSecond)}/s';
}
