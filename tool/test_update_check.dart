/// 手动验证更新检测逻辑（不启 UI）。
/// dart run tool/test_update_check.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const releasesUrl =
    'https://api.github.com/repos/AstralNext/AstralGame/releases?per_page=20';

String normalize(String version) {
  var s = version.trim();
  if (s.toLowerCase().startsWith('v')) s = s.substring(1).trim();
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  return s;
}

bool looksLikeSemverTag(String tag) {
  final core = normalize(tag).split('-').first;
  return RegExp(r'^\d+\.\d+').hasMatch(core);
}

bool isNewer(String candidate, String current) {
  final latest = normalize(candidate);
  final curr = normalize(current);
  if (latest.isEmpty || curr.isEmpty) return false;
  List<int> parts(String v) =>
      normalize(v).split('-').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final c = parts(curr);
  final l = parts(latest);
  for (var i = 0; i < 3; i++) {
    final cv = i < c.length ? c[i] : 0;
    final lv = i < l.length ? l[i] : 0;
    if (lv > cv) return true;
    if (lv < cv) return false;
  }
  return false;
}

Future<void> main() async {
  stdout.writeln('GET $releasesUrl');
  final res = await http.get(
    Uri.parse(releasesUrl),
    headers: {
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'astral-game',
    },
  ).timeout(const Duration(seconds: 15));
  stdout.writeln('HTTP ${res.statusCode}');
  if (res.statusCode != 200) {
    stderr.writeln(res.body);
    exitCode = 1;
    return;
  }

  final list = jsonDecode(res.body);
  if (list is! List) {
    stderr.writeln('body 不是 list');
    exitCode = 1;
    return;
  }

  Map<String, dynamic>? picked;
  for (final item in list) {
    if (item is! Map) continue;
    final r = Map<String, dynamic>.from(item);
    final tag = '${r['tag_name'] ?? ''}';
    stdout.writeln(
      '  - $tag draft=${r['draft']} prerelease=${r['prerelease']}',
    );
    if (r['draft'] == true) continue;
    if (r['prerelease'] == true) continue; // 默认非 beta
    if (!looksLikeSemverTag(tag)) continue;
    picked ??= r;
  }

  if (picked == null) {
    stderr.writeln('没有可用正式 release（与 UpdateService 默认频道一致）');
    exitCode = 2;
    return;
  }

  final latest = '${picked['tag_name']}';
  stdout.writeln('\n选中最新正式版: $latest');
  stdout.writeln('html_url: ${picked['html_url']}');

  for (final current in ['1.0.2', '1.0.3', 'v1.0.3', '1.0.4']) {
    final need = isNewer(latest, current);
    stdout.writeln(
      '当前=$current → ${need ? "应提示更新" : "已是最新/更高"}',
    );
  }
}
