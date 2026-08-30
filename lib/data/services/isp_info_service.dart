import 'dart:async';

import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:charset_converter/charset_converter.dart';
import 'package:http/http.dart' as http;
import 'package:signals/signals_core.dart';

/// 本机运营商/网络归属信息。
///
/// 仅使用 pconline（腾讯 IP 查询）：
///   https://whois.pconline.com.cn/ipJson.jsp?json=true
/// 返回全中文：`{"pro":"山东省","city":"临沂市","addr":"山东省临沂市 电信"}`
///
/// ⚠️ 该接口响应体为 GBK 编码（Content-Type 声明 charset=GBK），
/// 不能用 http.Response.body（Dart 默认 latin1 解码会乱码），
/// 必须用 [charset_converter] 手动解 GBK。
class IspInfoService {
  IspInfoService(this._connectivity);

  final ConnectivityStatusService _connectivity;
  void Function()? _effectDispose;
  Timer? _debounceTimer;
  String? _lastFetchedIp;

  /// 当前展示文本，例如 `山东省 临沂市 · 电信`。
  final label = signal<String>('');

  /// 正在拉取中。
  final loading = signal<bool>(false);

  static const _url =
      'https://whois.pconline.com.cn/ipJson.jsp?json=true';

  /// 从 pconline 的 addr 字段（如 "山东省临沂市 电信"）提取中文运营商名。
  /// 运营商总是 addr 最后一个空格之后的部分。
  /// 如果 addr 里没空格或最后部分不含运营商关键字，返回空串。
  static String _extractIsp(String addr) {
    final trimmed = addr.trim();
    if (trimmed.isEmpty) return '';

    // 找最后一个空格
    final idx = trimmed.lastIndexOf(' ');
    if (idx < 0) return ''; // 没空格，说明没运营商
    final tail = trimmed.substring(idx + 1);

    // 验证 tail 是否像运营商（包含常见关键字）
    const keywords = [
      '电信', '联通', '移动', '广电', '铁通', '鹏博士',
      '长城', '华数', '东方有线', '世纪互联', 'CNISP',
      '教育网', '科技网', '阿里云', '腾讯云', '华为云',
      '百度云', '京东云', 'Unknown',
    ];
    for (final kw in keywords) {
      if (tail.contains(kw)) return tail;
    }

    // 虽然没命中关键字，但也返回最后部分（可能是境外运营商或新运营商）
    return tail;
  }

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

      // ⚠️ 关键：pconline 返回 GBK。
      // charset_converter 是平台实现，不同平台认的 charset 名不一样：
      //   Windows: GB2312 / GB18030 / CP936 / windows-936 （"GBK" 有时不认）
      //   Android: "GBK" 最稳
      // 所以按优先级挨个试，直到一个成功。
      const charsetCandidates = [
        'GBK', 'GB18030', 'GB2312', 'CP936', 'windows-936', 'cp936',
      ];
      String? body;
      String? usedCharset;
      for (final cs in charsetCandidates) {
        try {
          body = await CharsetConverter.decode(cs, response.bodyBytes);
          usedCharset = cs;
          break;
        } catch (_) {
          // 这个 charset 不认，试下一个
        }
      }
      if (body == null) {
        appLogger.w('[IspInfo] 所有 GBK 变体 charset 都不被当前平台支持');
        return;
      }
      appLogger.i('[IspInfo] 解码成功 charset=$usedCharset; body=$body');
      final decoded = body!;

      final m = _extractKeys(decoded, {'ip', 'pro', 'city', 'addr', 'err'});

      if ((m['err'] ?? '').isNotEmpty) {
        appLogger.w('[IspInfo] pconline err=${m['err']}');
        return;
      }

      final ip = m['ip'] ?? '';
      if (ip.isEmpty) {
        appLogger.w('[IspInfo] 未返回 IP');
        return;
      }

      // IP 没变就跳过（省请求）
      if (ip == _lastFetchedIp) {
        appLogger.i('[IspInfo] IP 未变 ($ip)，跳过');
        return;
      }
      _lastFetchedIp = ip;

      final pro = (m['pro'] ?? '').trim();
      final city = (m['city'] ?? '').trim();
      final addr = (m['addr'] ?? '').trim();

      final location = [pro, city].where((s) => s.isNotEmpty).join(' ');
      final isp = _extractIsp(addr);

      // 运营商为空时兜底"未知运营商"
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
      appLogger.i('[IspInfo] ✅ 归属: $newLabel (addr=$addr)');
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
