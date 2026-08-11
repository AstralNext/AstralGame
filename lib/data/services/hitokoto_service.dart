import 'dart:convert';

import 'package:http/http.dart' as http;

/// 一言（Hitokoto）一句。
class HitokotoQuote {
  const HitokotoQuote({
    required this.text,
    this.from,
    this.fromWho,
  });

  final String text;
  final String? from;
  final String? fromWho;

  /// 副标题：作者 · 出处（有则拼）。
  String get attribution {
    final who = fromWho?.trim() ?? '';
    final src = from?.trim() ?? '';
    if (who.isNotEmpty && src.isNotEmpty && who != src) {
      return '$who · $src';
    }
    if (who.isNotEmpty) return who;
    if (src.isNotEmpty) return src;
    return '';
  }
}

/// https://v1.hitokoto.cn
class HitokotoService {
  HitokotoService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  /// 仅动画 / 漫画 / 网易云（`c` 可多选）。
  static final _uri = Uri.parse(
    'https://v1.hitokoto.cn/?c=a&c=b&c=j&encode=json&charset=utf-8',
  );

  Future<HitokotoQuote> fetch() async {
    final res = await _client.get(_uri).timeout(const Duration(seconds: 6));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('一言请求失败：${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('一言返回非 JSON 对象');
    }
    final text = '${decoded['hitokoto'] ?? ''}'.trim();
    if (text.isEmpty) {
      throw const FormatException('一言正文为空');
    }
    return HitokotoQuote(
      text: text,
      from: decoded['from']?.toString(),
      fromWho: decoded['from_who']?.toString(),
    );
  }
}
