import 'dart:convert';

import 'package:http/http.dart' as http;

/// 栗次元随机壁纸（https://t.alcy.cc）。
class AlcyWallpaperService {
  AlcyWallpaperService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 宽屏横图。
  static const wideCategory = 'pc';

  /// 窄屏竖图。
  static const narrowCategory = 'mp';

  /// 拉取一条随机图直链；[narrow] 为 true 用 mp，否则 pc。
  Future<String> fetchImageUrl({required bool narrow}) async {
    final category = narrow ? narrowCategory : wideCategory;
    final uri = Uri.parse('https://t.alcy.cc/json?$category');
    final res = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('壁纸请求失败：${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('壁纸返回非 JSON 对象');
    }
    final data = decoded['data'];
    String? link;
    if (data is Map) {
      link = data['link']?.toString();
    } else if (decoded['link'] != null) {
      link = decoded['link']?.toString();
    }
    final url = link?.trim() ?? '';
    if (url.isEmpty || !url.startsWith('http')) {
      throw const FormatException('壁纸链接无效');
    }
    return url;
  }

  void close() => _client.close();
}
