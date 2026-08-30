import 'dart:async';

import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:signals/signals_core.dart';

/// 本机运营商/网络归属信息。
///
/// 多数据源轮询兜底（免费公共 IP 归属 API 偶尔挂），仅在网络承载变化时
/// 重新拉取，避免触发频率限制。
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
    appLogger.i('[IspInfoService] start() — 立即发起首次拉取');
    _fetchNow();
    _effectDispose = effect(() {
      final kind = _connectivity.current.value;
      appLogger.i('[IspInfoService] effect 触发，当前网络: $kind');
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

  /// 依次尝试多个 API，第一个成功的结果被采用。
  static const _endpoints = [
    // http，中文返回，需要 Android usesCleartextTraffic
    _Endpoint('http://ip-api.com/json/?lang=zh-CN&fields=status,isp,org,regionName,city,query',
        _parseIpApi),
    // https，英文但更稳定，asn/as 字段含运营商
    _Endpoint('https://api.ip2location.io/', _parseIp2Location),
  ];

  Future<void> _fetchNow() async {
    loading.value = true;
    try {
      for (final ep in _endpoints) {
        try {
          appLogger.i('[IspInfo] 尝试 ${ep.url}');
          final response = await http
              .get(Uri.parse(ep.url))
              .timeout(const Duration(seconds: 6));
          if (response.statusCode != 200) {
            appLogger.w('[IspInfo] ${ep.url} → HTTP ${response.statusCode}');
            continue;
          }
          final result = ep.parse(response.body);
          if (result == null) {
            appLogger.w('[IspInfo] ${ep.url} → 解析失败');
            continue;
          }
          final ip = result['ip'] ?? '';
          if (ip.isNotEmpty && ip == _lastFetchedIp) {
            appLogger.i('[IspInfo] IP 未变 ($ip)，跳过');
            return;
          }
          _lastFetchedIp = ip;

          final isp = result['isp'] ?? '';
          final region = result['region'] ?? '';
          final city = result['city'] ?? '';

          final location = [region, city].where((s) => s.isNotEmpty).join(' ');
          final parts = <String>[
            if (isp.isNotEmpty) isp,
            if (location.isNotEmpty) location,
          ];
          final newLabel = parts.join(' · ');
          if (newLabel.isEmpty) {
            appLogger.w('[IspInfo] 所有 API 均未能解析出有效信息');
            continue;
          }
          if (newLabel != label.value) {
            label.value = newLabel;
          }
          appLogger.i('[IspInfo] ✅ 归属: $newLabel');
          return; // 第一个成功就停
        } catch (e) {
          appLogger.w('[IspInfo] ${ep.url} → 异常: $e');
          continue;
        }
      }
      appLogger.w('[IspInfo] ❌ 所有 API 都失败，label 保持 "${label.value}"');
    } finally {
      loading.value = false;
    }
  }

  // ---- 解析器 ----

  static Map<String, String>? _parseIpApi(String body) {
    final m = _extractKeys(body, {'status', 'isp', 'org', 'regionName', 'city', 'query'});
    if (m['status'] != 'success') return null;
    return {
      'isp': (m['isp'] ?? '').trim().isEmpty ? (m['org'] ?? '').trim() : (m['isp'] ?? '').trim(),
      'region': (m['regionName'] ?? '').trim(),
      'city': (m['city'] ?? '').trim(),
      'ip': (m['query'] ?? '').trim(),
    };
  }

  static Map<String, String>? _parseIp2Location(String body) {
    final m = _extractKeys(body, {
      'ip', 'country_name', 'region_name', 'city_name', 'as',
    });
    if ((m['ip'] ?? '').isEmpty) return null;
    return {
      'isp': (m['as'] ?? '').trim(),
      'region': (m['country_name'] ?? '').trim(),
      'city': [m['region_name'], m['city_name']]
          .where((s) => s != null && s.isNotEmpty)
          .join(' '),
      'ip': (m['ip'] ?? '').trim(),
    };
  }

  /// 极简 JSON → Map（正则提取指定 key 的字符串值，避免复杂 JSON 依赖）。
  static Map<String, String> _extractKeys(String body, Set<String> keys) {
    final result = <String, String>{};
    for (final k in keys) {
      final m = RegExp('"${RegExp.escape(k)}\\s*:\\s*"([^"]*)"').firstMatch(body);
      if (m != null) result[k] = m.group(1)!;
    }
    return result;
  }
}

class _Endpoint {
  final String url;
  final Map<String, String>? Function(String body) parse;
  const _Endpoint(this.url, this.parse);
}
