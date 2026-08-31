import 'dart:async';
import 'dart:convert';

import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:signals/signals_core.dart';

class IspInfoService {
  IspInfoService(this._connectivity);

  final ConnectivityStatusService _connectivity;
  void Function()? _effectDispose;
  Timer? _debounceTimer;

  final label = signal<String>('');
  final loading = signal<bool>(false);

  // 单一数据源：ipip.net 免费接口。自动识别客户端真实 IP，
  // 无需传参，UTF-8 JSON，location = [国家, 省, 市, 区县, 运营商]（全中文）。
  static const _apiUrl = 'https://myip.ipip.net/json';
  static const _timeout = Duration(seconds: 8);
  static const _unknown = '未知运营商';

  void start() {
    if (_effectDispose != null) return;
    appLogger.i('[IspInfoService] start()');
    _fetchNow();
    _effectDispose = effect(() {
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
      final resp = await http.get(Uri.parse(_apiUrl)).timeout(_timeout);
      if (resp.statusCode != 200) {
        appLogger.w('[IspInfo] ipip HTTP ${resp.statusCode}');
        label.value = _unknown;
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final newLabel = _parseLabel(data) ?? _unknown;
      if (newLabel != label.value) label.value = newLabel;
      appLogger.i('[IspInfo] ✅ 归属: $newLabel');
    } catch (e) {
      appLogger.e('[IspInfo] 异常: $e');
      if (label.value.isEmpty) label.value = _unknown;
    } finally {
      loading.value = false;
    }
  }

  /// 从响应中解析「国家+省 运营商」，如 `中国山东 电信`；解析不出有效内容返回 null。
  static String? _parseLabel(Map<String, dynamic> json) {
    if (json['ret'] != 'ok') return null;
    final loc =
        ((json['data'] as Map<String, dynamic>?)?['location'] as List?) ??
        const [];
    String part(int i) => (loc.length > i ? '${loc[i]}' : '').trim();

    final place = '${part(0)}${part(1)}'; // 国家+省，如「中国山东」
    final isp = part(4);
    if (place.isEmpty && isp.isEmpty) return null;
    return place.isEmpty ? isp : '$place $isp';
  }
}
