import 'package:astral_game/data/models/speed_test_node.dart';
import 'package:astral_game/data/models/speed_test_result.dart';
import 'package:astral_game/data/models/speed_test_snapshot.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/speed_test_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:signals/signals.dart';

class SpeedTestState {
  SpeedTestState(this._service, [this._settings]) {
    final snapshot = _settings?.getSpeedTestSnapshot();
    if (snapshot != null) {
      result.value = SpeedTestResult(
        downloadMbps: snapshot.downloadMbps,
        uploadMbps: snapshot.uploadMbps,
        lossRate: snapshot.lossRate,
      );
      resultFromHistory.value = true;
    }
  }

  final SpeedTestService _service;
  final AppSettingsService? _settings;

  final nodes = signal<List<SpeedTestNode>>(const []);

  final loading = signal(false);

  final error = signal<String?>(null);

  final selected = signal<SpeedTestNode?>(null);

  final running = signal(false);
  final phase = signal<SpeedTestPhase?>(null);

  final result = signal<SpeedTestResult?>(null);
  final resultFromHistory = signal<bool>(false);
  final samples = signal<List<SpeedTestSample>>(const []);

  final liveDownloadLatencyMs = signal<double?>(null);
  final liveUploadLatencyMs = signal<double?>(null);

  bool _defaultsApplied = false;

  Future<void> loadNodes({bool forceRefresh = false}) async {
    if (loading.value) return;
    loading.value = true;
    error.value = null;
    try {
      nodes.value = await _service.fetchNodes(forceRefresh: forceRefresh);
      _ensureSelection();
    } on SpeedTestException catch (e) {
      error.value = e.message;
    } catch (e) {
      error.value = '$e';
    } finally {
      loading.value = false;
    }
  }

  void applyLocalDefaults({
    required String localProvince,
    required String localIsp,
  }) {
    if (_defaultsApplied || nodes.value.isEmpty) return;
    if (localProvince.isEmpty && localIsp.isEmpty) return;
    _defaultsApplied = true;
    selected.value =
        _matchByLocation(localProvince, localIsp) ?? nodes.value.first;
  }

  void selectNode(SpeedTestNode node) {
    _defaultsApplied = true;
    selected.value = node;
  }

  Future<void> startTest() async {
    final node = selected.value;
    if (node == null || running.value) return;
    running.value = true;
    resultFromHistory.value = false;
    result.value = null;
    samples.value = const [];
    liveDownloadLatencyMs.value = null;
    liveUploadLatencyMs.value = null;
    phase.value = SpeedTestPhase.latency;
    try {
      final measured = await _service.measure(
        node,
        onPhase: (value) => phase.value = value,
        onLatency: (latencyPhase, latencyMs) => switch (latencyPhase) {
          SpeedTestPhase.latency => null,
          SpeedTestPhase.download => liveDownloadLatencyMs.value = latencyMs,
          SpeedTestPhase.upload => liveUploadLatencyMs.value = latencyMs,
        },
        onSample: (samplePhase, elapsed, mbps) {
          samples.value = [
            ...samples.value,
            SpeedTestSample(phase: samplePhase, elapsed: elapsed, mbps: mbps),
          ];
        },
      );
      result.value = measured;
      final snapshot = SpeedTestSnapshot.fromResult(measured);
      if (snapshot != null) {
        try {
          await _settings?.setSpeedTestSnapshot(snapshot);
        } catch (e) {
          appLogger.w('[SpeedTest] 保存测速结果失败', error: e);
        }
      }
    } on SpeedTestException catch (e) {
      result.value = SpeedTestResult.failure(e.message);
    } catch (e) {
      result.value = SpeedTestResult.failure('$e');
    } finally {
      running.value = false;
      phase.value = null;
    }
  }

  SpeedTestNode? _matchByLocation(String province, String isp) {
    final all = nodes.value;
    SpeedTestNode? sameOperator;
    SpeedTestNode? sameProvince;
    for (final node in all) {
      final locationHit = _matches(node.province, province);
      final operatorHit = _matches(node.operator, isp);
      if (locationHit && operatorHit) return node;
      if (operatorHit) sameOperator ??= node;
      if (locationHit) sameProvince ??= node;
    }
    return sameOperator ?? sameProvince;
  }

  static bool _matches(String value, String wanted) {
    if (value.isEmpty || wanted.isEmpty) return false;
    return value.contains(wanted) || wanted.contains(value);
  }

  void _ensureSelection() {
    final current = selected.value;
    if (current != null &&
        nodes.value.any((node) => node.endpoint == current.endpoint)) {
      return;
    }
    selected.value = nodes.value.isEmpty ? null : nodes.value.first;
  }
}
