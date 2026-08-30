import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:http/http.dart' as http;
import 'package:signals/signals_core.dart';

/// 本机运营商/网络归属信息。
///
/// 只使用 pconline 接口: https://whois.pconline.com.cn/ipJson.jsp?json=true
/// 接口直接返回全中文：`{"addr":"山东省临沂市 电信"}`，无需运营商映射。
///
/// ⚠️ GBK 编码：Dart 标准库只有 utf8/ascii/latin1，
/// 使用 charset_converter (Flutter plugin) 调系统原生 GBK 解码。
/// 不同平台对 charset 名的识别不一致，因此逐个尝试多种写法。
class IspInfoService {
  IspInfoService(this._connectivity);

  final ConnectivityStatusService _connectivity;
  void Function()? _effectDispose;
  Timer? _debounceTimer;
  String? _lastFetchedIp;

  final label = signal<String>('');
  final loading = signal<bool>(false);

  static const _url = 'https://whois.pconline.com.cn/ipJson.jsp?json=true';

  /// 不同平台对 GBK 的名字不同，按顺序试直到成功：
  ///   • Android (ICU):          'GBK'、'GB18030'
  ///   • iOS/macOS (CFString):   'GBK'、'GB18030'、'GB2312'
  ///   • Windows (codepage):     'windows-936'、'CP936'、'GB2312'
  ///   • Linux (iconv):          'GBK'、'GB18030'、'GB2312'
  static const _charsetCandidates = [
    'GBK',
    'GB18030',
    'windows-936',
    'CP936',
    'GB2312',
    'cp936',
    'GBK2312',
    'Shift_JISX0213',
  ];

  static Future<String> _decodeGbk(Uint8List bytes) async {
    if (bytes.isEmpty) return '';

    for (final name in _charsetCandidates) {
      try {
        return await CharsetConverter.decode(name, bytes);
      } catch (_) {
        // 这个名字当前平台不认得，试下一个
      }
    }
    // 全失败：至少把 ASCII 部分（IP 是数字+点）解出来，中文部分变成 ?
    return latin1.decode(bytes, allowInvalid: true);
  }

  /// 从 pconline addr 字段提取省市 + 运营商。
  /// 示例:
  ///   "山东省临沂市 电信"          → ("山东省 临沂市", "电信")
  ///   "广东省深圳市南山区 电信ADSL" → ("广东省 深圳市 南山区", "电信ADSL")
  ///   "美国"                      → ("美国", "")
  static ({String location, String isp}) _splitAddr(String addr) {
    final trimmed = addr.trim();
    if (trimmed.isEmpty) return (location: '', isp: '');
    final idx = trimmed.lastIndexOf(' ');
    if (idx < 0) {
      return (location: trimmed, isp: '');
    }
    final rawLoc = trimmed.substring(0, idx);
    final tail = trimmed.substring(idx + 1);

    const ispKeywords = [
      '电信', '联通', '移动', '广电', '铁通', '鹏博士',
      '长城', '华数', '东方有线', '世纪互联', 'CNISP',
      '教育网', '科技网', '阿里云', '腾讯云', '华为云',
      '百度云', '京东云', 'ADSL', '宽带', '代理上网',
      '网吧', '校园网',
    ];
    for (final kw in ispKeywords) {
      if (tail.contains(kw)) {
        final location = rawLoc
            .replaceAllMapped(
              RegExp(r'([^区县省市自治特别])([省市自治区特别行政区])'),
              (m) => '${m.group(1)}${m.group(2)} ',
            )
            .replaceAll('  ', ' ')
            .trim();
        return (location: location, isp: tail);
      }
    }
    return (location: trimmed, isp: '');
  }

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
      appLogger.i('[IspInfo] 请求 pconline');
      final resp = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        appLogger.w('[IspInfo] HTTP ${resp.statusCode}');
        return;
      }

      final body = await _decodeGbk(resp.bodyBytes);
      appLogger.i('[IspInfo] pconline: $body');

      final ip = _jsonStr(body, 'ip');
      if (ip.isEmpty) {
        appLogger.w('[IspInfo] 无 IP');
        return;
      }
      if (ip == _lastFetchedIp) {
        appLogger.i('[IspInfo] IP 未变 ($ip) 跳过');
        return;
      }
      _lastFetchedIp = ip;

      final err = _jsonStr(body, 'err');
      if (err.isNotEmpty) {
        appLogger.w('[IspInfo] pconline err=$err');
        return;
      }

      final pro = _jsonStr(body, 'pro');
      final city = _jsonStr(body, 'city');
      final addr = _jsonStr(body, 'addr');

      final splitted = _splitAddr(addr);
      final location = splitted.location.isEmpty
          ? [pro, city].where((s) => s.isNotEmpty).join(' ')
          : splitted.location;
      final isp = splitted.isp;
      final ispOrUnknown = isp.isEmpty ? '未知运营商' : isp;

      final parts = <String>[
        if (location.isNotEmpty) location,
        ispOrUnknown,
      ];
      final newLabel = parts.join(' · ');

      if (newLabel != label.value) {
        label.value = newLabel;
      }
      appLogger.i('[IspInfo] ✅ 归属: $newLabel (addr=$addr)');
    } catch (e) {
      appLogger.e('[IspInfo] 异常: $e');
      if (label.value.isEmpty) {
        label.value = '未知运营商';
      }
    } finally {
      loading.value = false;
    }
  }

  static String _jsonStr(String body, String key) {
    final m = RegExp(
      '"${RegExp.escape(key)}"\\s*:\\s*"([^"]*)"',
    ).firstMatch(body);
    return m?.group(1) ?? '';
  }
}
