import 'dart:async';

import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:signals/signals_core.dart';

/// 本机运营商/网络归属信息。
///
/// 使用 ip-api.com（免费、中文、UTF-8），仅在网络承载变化时重新拉取。
/// Dart http 库能正确处理其 UTF-8 响应（pconline 返回 GBK 需要额外解码，放弃）。
class IspInfoService {
  IspInfoService(this._connectivity);

  final ConnectivityStatusService _connectivity;
  void Function()? _effectDispose;
  Timer? _debounceTimer;
  String? _lastFetchedIp;

  /// 当前展示文本，例如 `山东省 济南市 · 中国电信`。
  final label = signal<String>('');

  /// 正在拉取中。
  final loading = signal<bool>(false);

  static const _url =
      'http://ip-api.com/json/?lang=zh-CN&fields=status,isp,regionName,city,query';

  /// 英文/缩写运营商 → 中文映射。
  static const _ispMap = {
    'Chinanet': '中国电信',
    'China Telecom': '中国电信',
    'China Unicom': '中国联通',
    'Unicom': '中国联通',
    'China Mobile': '中国移动',
    'CMCC': '中国移动',
    'China Tietong': '中国铁通',
    'Tietong': '中国铁通',
    'China Railcom': '中国铁通',
    'China CTT': '中国广电',
    'Cable Television': '中国广电',
  };

  static String _mapIsp(String isp) {
    final trimmed = isp.trim();
    if (trimmed.isEmpty) return '';
    // 直接匹配
    for (final entry in _ispMap.entries) {
      if (trimmed.toLowerCase() == entry.key.toLowerCase()) return entry.value;
    }
    // 包含匹配（如 "Chinanet (some description)"）
    for (final entry in _ispMap.entries) {
      if (trimmed.toLowerCase().contains(entry.key.toLowerCase())) return entry.value;
    }
    // 没映射就原样返回
    return trimmed;
  }

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

  Future<void> _fetchNow() async {
    loading.value = true;
    try {
      appLogger.i('[IspInfo] 发起请求: $_url');
      final response = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        appLogger.w('[IspInfo] HTTP ${response.statusCode}');
        return;
      }

      // ip-api.com 返回的 JSON 里 status 不是 success 就说明限流/失败
      final body = response.body;
      appLogger.i('[IspInfo] raw body: $body');

      final m = _extractKeys(body, {'status', 'isp', 'regionName', 'city', 'query'});
      if (m['status'] != 'success') {
        appLogger.w('[IspInfo] status != success: ${m['status']}');
        return;
      }

      final ip = m['query'] ?? '';
      if (ip.isEmpty) {
        appLogger.w('[IspInfo] 未返回 IP');
        return;
      }

      // IP 没变就跳过
      if (ip == _lastFetchedIp) {
        appLogger.i('[IspInfo] IP 未变 ($ip)，跳过');
        return;
      }
      _lastFetchedIp = ip;

      final region = (m['regionName'] ?? '').trim();
      final city = (m['city'] ?? '').trim();
      final ispRaw = (m['isp'] ?? '').trim();
      final isp = _mapIsp(ispRaw);

      final location = [region, city].where((s) => s.isNotEmpty).join(' ');
      // 运营商为空时显示"未知运营商"，确保始终有值
      final ispOrUnknown = isp.isEmpty ? '未知运营商' : isp;
      final parts = <String>[
        if (location.isNotEmpty) location,
        ispOrUnknown,
      ];
      final newLabel = parts.join(' · ');

      if (newLabel.isEmpty) {
        appLogger.w('[IspInfo] 未能解析出有效信息');
        return;
      }

      if (newLabel != label.value) {
        label.value = newLabel;
      }
      appLogger.i('[IspInfo] ✅ 归属: $newLabel (raw isp=$ispRaw)');
    } catch (e) {
      appLogger.e('[IspInfo] 异常: $e');
      // API 彻底失败时兜底
      if (label.value.isEmpty) {
        label.value = '未知运营商';
      }
    } finally {
      loading.value = false;
    }
  }

  /// 极简 JSON → Map（正则提取指定 key 的字符串值）。
  static Map<String, String> _extractKeys(String body, Set<String> keys) {
    final result = <String, String>{};
    for (final k in keys) {
      final m = RegExp('"${RegExp.escape(k)}\\s*:\\s*"([^"]*)"').firstMatch(body);
      if (m != null) result[k] = m.group(1)!;
    }
    return result;
  }
}
