import 'dart:convert';

import 'package:astral_game/data/models/speed_test_result.dart';

class SpeedTestSnapshot {
  const SpeedTestSnapshot({
    required this.downloadMbps,
    required this.uploadMbps,
    required this.testedAtMs,
    this.lossRate,
  });

  final double downloadMbps;

  final double uploadMbps;

  final double? lossRate;

  final int testedAtMs;

  static SpeedTestSnapshot? fromResult(SpeedTestResult result) {
    final download = result.downloadMbps;
    final upload = result.uploadMbps;
    if (!result.ok || download == null || upload == null) return null;
    return SpeedTestSnapshot(
      downloadMbps: download,
      uploadMbps: upload,
      lossRate: result.lossRate,
      testedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
    'download': downloadMbps,
    'upload': uploadMbps,
    'loss': lossRate,
    'testedAt': testedAtMs,
  };

  static SpeedTestSnapshot? tryParse(Object? raw) {
    Object? decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Map) return null;
    final download = _toDouble(decoded['download']);
    final upload = _toDouble(decoded['upload']);
    if (download == null || upload == null) return null;
    final testedAt = decoded['testedAt'];
    return SpeedTestSnapshot(
      downloadMbps: download,
      uploadMbps: upload,
      lossRate: _toDouble(decoded['loss']),
      testedAtMs: testedAt is num ? testedAt.toInt() : 0,
    );
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
