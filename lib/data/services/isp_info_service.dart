import 'dart:async';

import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:signals/signals_core.dart';

/// 本机运营商/网络归属信息。
///
/// 数据源 ip-api.com（免费、无 key、中文返回）。仅在网络承载变化时
/// 重新拉取，避免触发频率限制（45/min）。
class IspInfoService {
  IspInfoService(this._connectivity);

  final ConnectivityStatusService _connectivity;
  void Function()? _effectDispose;
  Timer? _debounceTimer;
  String? _lastFetchedIp;

  /// 当前展示文本，例如 `中国联通 · 北京`。
  final label = signal<String>('');

  /// 正在拉取中。
  final loading = signal<bool>(false);

  /// 启动：立即拉一次 + 网络变化时自动刷新。
  void start() {
    if (_effectDispose != null) return;
    _fetchNow();
    _effectDispose = effect(() {
      // 读取 signal 建立追踪，值变化时自动回调
      final kind = _connectivity.current.value;
      if (kind == NetworkKind.none || kind == NetworkKind.unknown) return;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 800), _fetchNow);
    });
  }

  Future<void> dispose() async {
    _effectDispose?.call();
    _effectDispose = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  Future<void> _fetchNow() async {
    loading.value = true;
    try {
      final uri = Uri.parse(
        'http://ip-api.com/json/?lang=zh-CN&fields=status,isp,org,regionName,city,query',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        appLogger.w('[IspInfo] HTTP ${response.statusCode}');
        return;
      }
      final body = response.body;
      final m = _extractMap(body);
      if (m['status'] != 'success') {
        appLogger.w('[IspInfo] status=${m['status']}');
        return;
      }
      final ip = m['query'] ?? '';
      if (ip.isNotEmpty && ip == _lastFetchedIp) {
        return; // IP 没变，归属大概率没变
      }
      _lastFetchedIp = ip;

      final isp = (m['isp'] ?? '').trim();
      final region = (m['regionName'] ?? '').trim();
      final city = (m['city'] ?? '').trim();

      final displayIsp = isp.isNotEmpty ? isp : (m['org'] ?? '').trim();
      final location = [region, city].where((s) => s.isNotEmpty).join(' ');

      final parts = <String>[
        if (displayIsp.isNotEmpty) displayIsp,
        if (location.isNotEmpty) location,
      ];
      final newLabel = parts.join(' · ');
      if (newLabel.isNotEmpty && newLabel != label.value) {
        label.value = newLabel;
      }
      appLogger.i('[IspInfo] 归属: $newLabel');
    } catch (e) {
      appLogger.w('[IspInfo] 拉取失败: $e');
    } finally {
      loading.value = false;
    }
  }

  /// 极简 JSON 字符串 → Map（只提取我们关心的几个 key）。
  Map<String, String> _extractMap(String body) {
    final result = <String, String>{};
    const keys = {'status', 'isp', 'org', 'regionName', 'city', 'query'};
    for (final k in keys) {
      final m = RegExp('"${RegExp.escape(k)}\\s*:\\s*"([^"]*)"').firstMatch(body);
      if (m != null) result[k] = m.group(1)!;
    }
    return result;
  }
}
