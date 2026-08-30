import 'dart:async';
import 'dart:typed_data';

import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:signals/signals_core.dart';

/// 本机运营商/网络归属信息。
///
/// 两步走，全程 UTF-8：
///   1. pconline 拿真实公网 IP：
///      pconline 虽然响应体是 GBK 编码中文，但 IP 字段是纯 ASCII 数字，
///      直接在 bodyBytes 里搜 `"ip":"` 的 ASCII bytes，不用做任何字符解码。
///      选它是因为只有它能识别"真实客户端公网 IP"
///      （其他接口 ipify 亚马逊代理、搜狐返回 127.0.0.1、ip-api 返回 CDN IP）
///
///   2. 百度开放平台 oe=utf8 接口拿归属：
///      http://opendata.baidu.com/api.php?resource_id=6006&oe=utf8&query=IP
///      Content-Type: application/json;charset=utf-8 ✅
///      location 字段是拼接好的中文，如 "山东省临沂市 电信"
///      省/市/运营商全在里面，不用映射表。
class IspInfoService {
  IspInfoService(this._connectivity);

  final ConnectivityStatusService _connectivity;
  void Function()? _effectDispose;
  Timer? _debounceTimer;
  String? _lastFetchedIp;

  final label = signal<String>('');
  final loading = signal<bool>(false);

  /// Step 1: pconline 拿真实 IP（只看 ASCII bytes，不解 GBK）
  static const _ipUrl = 'https://whois.pconline.com.cn/ipJson.jsp?json=true';

  /// Step 2: 百度 UTF-8 接口拿归属（oe=utf8 强制 UTF-8）
  static const _geoPrefix =
      'http://opendata.baidu.com/api.php?co=&resource_id=6006&oe=utf8&query=';

  /// 在 pconline 的原始响应 bytes 里直接找 ASCII 序列 `"ip":"1.2.3.4"`
  /// 完全不需要字符解码，也不依赖任何三方包。
  static String? _extractIpFromBytes(Uint8List bytes) {
    // 要匹配的 ASCII 序列: "\"ip\":\""
    // 引号(34) i(105) p(112) 引号(34) :(58) 引号(34)
    const sig = <int>[34, 105, 112, 34, 58, 34];
    for (int i = 0; i <= bytes.length - sig.length; i++) {
      bool hit = true;
      for (int j = 0; j < sig.length; j++) {
        if (bytes[i + j] != sig[j]) {
          hit = false;
          break;
        }
      }
      if (!hit) continue;
      final start = i + sig.length;
      var end = start;
      while (end < bytes.length && bytes[end] != 34) {
        end++; // 直到下一个引号
      }
      if (end > start && end <= bytes.length) {
        return String.fromCharCodes(Uint8List.sublistView(bytes, start, end));
      }
      break;
    }
    return null;
  }

  /// 把百度 location 拆成"位置"和"运营商"两段。
  /// 例: "山东省临沂市 电信"   → ("山东省 临沂市", "电信")
  /// 例: "北京市海淀区 联通ADSL" → ("北京市 海淀区", "联通ADSL")
  /// 例: "美国" (境外)          → ("美国", "")
  static ({String location, String isp}) _split(String baiduLocation) {
    final trimmed = baiduLocation.trim();
    if (trimmed.isEmpty) return (location: '', isp: '');
    final idx = trimmed.lastIndexOf(' ');
    if (idx < 0) {
      // 没有空格 → 境外 (如 "美国")
      return (location: trimmed, isp: '');
    }
    final rawAddr = trimmed.substring(0, idx);
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
        // 在"省""市"等字之间加空格，输出更清爽
        final location = rawAddr
            .replaceAllMapped(
              RegExp(r'([^区县省市自治特别])([省市自治区特别行政区])'),
              (m) => '${m.group(1)}${m.group(2)} ',
            )
            .replaceAll('  ', ' ')
            .trim();
        return (location: location, isp: tail);
      }
    }
    // tail 不像运营商
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
      // ===== Step 1: pconline 抓真实 IP =====
      appLogger.i('[IspInfo] Step1: pconline 拿真实 IP');
      final ipResp = await http
          .get(Uri.parse(_ipUrl))
          .timeout(const Duration(seconds: 8));
      if (ipResp.statusCode != 200) {
        appLogger.w('[IspInfo] pconline HTTP ${ipResp.statusCode}');
        return;
      }
      final ip = _extractIpFromBytes(ipResp.bodyBytes);
      if (ip == null || ip.isEmpty) {
        appLogger.w('[IspInfo] pconline 没抓到 IP');
        return;
      }
      appLogger.i('[IspInfo] 真实 IP = $ip');
      if (ip == _lastFetchedIp) {
        appLogger.i('[IspInfo] IP 未变，跳过');
        return;
      }
      _lastFetchedIp = ip;

      // ===== Step 2: 百度 UTF-8 拿归属 =====
      appLogger.i('[IspInfo] Step2: 百度 UTF-8 归属');
      final geoResp = await http
          .get(Uri.parse('$_geoPrefix$ip'))
          .timeout(const Duration(seconds: 8));
      if (geoResp.statusCode != 200) {
        appLogger.w('[IspInfo] 百度 HTTP ${geoResp.statusCode}');
        return;
      }
      final body = geoResp.body; // UTF-8 ✅
      appLogger.i('[IspInfo] 百度响应: $body');

      // 抓 location 字段 + status
      final locM =
          RegExp('"location"\\s*:\\s*"([^"]*)"').firstMatch(body);
      final statusM =
          RegExp('"status"\\s*:\\s*"?(-?\\d+)"?').firstMatch(body);
      if (locM == null) {
        appLogger.w('[IspInfo] 百度没返回 location');
        return;
      }
      if (statusM != null && statusM.group(1) != '0') {
        appLogger.w('[IspInfo] 百度 status != 0');
        return;
      }

      final rawLoc = locM.group(1)!;
      final parsed = _split(rawLoc);
      final ispOrUnknown = parsed.isp.isEmpty ? '未知运营商' : parsed.isp;
      final parts = <String>[
        if (parsed.location.isNotEmpty) parsed.location,
        ispOrUnknown,
      ];
      final newLabel = parts.join(' · ');
      if (newLabel != label.value) {
        label.value = newLabel;
      }
      appLogger.i('[IspInfo] ✅ 归属: $newLabel (baidu="$rawLoc")');
    } catch (e) {
      appLogger.e('[IspInfo] 异常: $e');
      if (label.value.isEmpty) label.value = '未知运营商';
    } finally {
      loading.value = false;
    }
  }
}
