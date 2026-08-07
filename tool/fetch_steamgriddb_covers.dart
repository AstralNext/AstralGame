/// 从 SteamGridDB 下载游戏 icon / grid 到 assets/games/。
///
/// 用法:
///   set STEAMGRIDDB_API_KEY=你的key
///   dart run tool/fetch_steamgriddb_covers.dart
///   dart run tool/fetch_steamgriddb_covers.dart --force
///
/// 无 Key 时：有 Steam AppID 的游戏回退到 Steam CDN（library_600x900）；
/// Minecraft 等无 Steam 的条目仍需要 API Key。
///
/// API Key: https://www.steamgriddb.com/profile/preferences/api
library;

import 'dart:convert';
import 'dart:io';

const _apiBase = 'https://www.steamgriddb.com/api/v2';
const _steamCdn =
    'https://cdn.cloudflare.steamstatic.com/steam/apps';

class _GameTarget {
  const _GameTarget({
    required this.id,
    this.steamAppId,
    this.sgdbGameId,
  });

  final String id;
  final int? steamAppId;
  final int? sgdbGameId;
}

/// 优先拉线上 gamerules；失败再读本地通用回退。
Future<List<_GameTarget>> _loadTargets(Directory root) async {
  Map? decoded;
  final client = HttpClient();
  try {
    final req = await client
        .getUrl(Uri.parse('https://astral.fan/gamerules.json'))
        .timeout(const Duration(seconds: 12));
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = await res.transform(utf8.decoder).join();
      final raw = jsonDecode(body);
      if (raw is Map) {
        decoded = raw;
        stdout.writeln('已从线上加载 gamerules.json');
      }
    }
  } catch (e) {
    stderr.writeln('线上规则加载失败: $e');
  } finally {
    client.close(force: true);
  }

  if (decoded == null) {
    final file = File('${root.path}/assets/games/rules.json');
    if (!file.existsSync()) {
      throw StateError('找不到远程规则，且无本地 ${file.path}');
    }
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! Map) {
      throw const FormatException('gamerules root must be object');
    }
    decoded = raw;
    stderr.writeln('警告：使用本地通用回退，封面目标可能很少');
  }

  final games = decoded['games'];
  if (games is! List) return const [];
  final out = <_GameTarget>[];
  for (final e in games) {
    if (e is! Map) continue;
    final id = '${e['id'] ?? ''}'.trim();
    if (id.isEmpty || id == 'other') continue;
    final steam = e['steam_app_id'];
    final sgdb = e['sgdb_game_id'];
    final steamAppId = steam is num ? steam.toInt() : null;
    final sgdbGameId = sgdb is num ? sgdb.toInt() : null;
    if (steamAppId == null && sgdbGameId == null) continue;
    out.add(_GameTarget(
      id: id,
      steamAppId: steamAppId,
      sgdbGameId: sgdbGameId,
    ));
  }
  return out;
}

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final key = Platform.environment['STEAMGRIDDB_API_KEY']?.trim() ?? '';
  if (key.isEmpty) {
    stdout.writeln(
      '未设置 STEAMGRIDDB_API_KEY，有 Steam AppID 的游戏将用 Steam CDN；'
      '无 Steam 的游戏需 API Key。\n'
      '申请: https://www.steamgriddb.com/profile/preferences/api',
    );
  }

  final root = _findProjectRoot();
  final targets = await _loadTargets(root);
  if (targets.isEmpty) {
    stderr.writeln('gamerules 中没有可拉取封面的游戏');
    exitCode = 1;
    return;
  }

  final client = HttpClient();
  try {
    for (final t in targets) {
      stdout.writeln('— ${t.id}');
      final dir = Directory('${root.path}/assets/games/${t.id}');
      await dir.create(recursive: true);

      if (key.isNotEmpty) {
        final sgdbId = await _resolveSgdbId(client, key, t);
        if (sgdbId == null) {
          stderr.writeln('  无法解析 SGDB id，尝试 Steam CDN');
          await _steamCdnFallback(client, t, dir, force);
          continue;
        }
        stdout.writeln('  sgdb=$sgdbId');
        await _downloadBestAsset(
          client: client,
          key: key,
          kind: 'icons',
          sgdbId: sgdbId,
          outFile: File('${dir.path}/icon.png'),
          force: force,
          query: 'types=static',
          preferFormats: const ['.png', '.webp', '.jpg', '.jpeg'],
        );
        await _downloadBestAsset(
          client: client,
          key: key,
          kind: 'grids',
          sgdbId: sgdbId,
          outFile: File('${dir.path}/grid.png'),
          force: force,
          query: 'dimensions=600x900&types=static',
          preferFormats: const ['.png', '.jpg', '.jpeg', '.webp'],
        );
        // Flutter 不支持 ICO：若 icon 缺失则用 grid 顶上
        await _ensureRasterIcon(dir);
      } else {
        await _steamCdnFallback(client, t, dir, force);
      }
    }
    stdout.writeln('完成。确认 pubspec.yaml 已声明 assets/games/，并核对 catalog 扩展名。');
  } finally {
    client.close(force: true);
  }
}

Future<void> _steamCdnFallback(
  HttpClient client,
  _GameTarget t,
  Directory dir,
  bool force,
) async {
  final appId = t.steamAppId;
  if (appId == null) {
    stderr.writeln('  跳过：无 Steam AppID 且无 API Key');
    return;
  }
  final url = '$_steamCdn/$appId/library_600x900.jpg';
  final grid = File('${dir.path}/grid.jpg');
  final icon = File('${dir.path}/icon.jpg');
  if (grid.existsSync() && icon.existsSync() && !force) {
    stdout.writeln('  skip Steam CDN (已存在)');
    return;
  }
  stdout.writeln('  Steam CDN ← $url');
  final bytes = await _downloadBytes(client, url);
  await grid.writeAsBytes(bytes, flush: true);
  await icon.writeAsBytes(bytes, flush: true);
  stdout.writeln('  写入 ${grid.path} / ${icon.path}');
}

Future<void> _ensureRasterIcon(Directory dir) async {
  for (final name in ['icon.png', 'icon.jpg', 'icon.webp']) {
    final f = File('${dir.path}/$name');
    if (!f.existsSync()) continue;
    final bytes = await f.readAsBytes();
    // ICO: 00 00 01 00
    if (bytes.length >= 4 &&
        bytes[0] == 0 &&
        bytes[1] == 0 &&
        bytes[2] == 1 &&
        bytes[3] == 0) {
      await f.delete();
      stdout.writeln('  删除不可用的 ICO icon');
      break;
    }
    return; // 已有可用 raster icon
  }
  for (final name in ['grid.png', 'grid.jpg', 'grid.webp']) {
    final grid = File('${dir.path}/$name');
    if (!grid.existsSync()) continue;
    final ext = name.substring(name.lastIndexOf('.'));
    final icon = File('${dir.path}/icon$ext');
    await grid.copy(icon.path);
    stdout.writeln('  icon 回退为 grid → ${icon.uri.pathSegments.last}');
    return;
  }
}

Directory _findProjectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('未找到含 pubspec.yaml 的项目根目录');
    }
    dir = parent;
  }
}

Future<int?> _resolveSgdbId(
  HttpClient client,
  String key,
  _GameTarget t,
) async {
  if (t.sgdbGameId != null) return t.sgdbGameId;
  final appId = t.steamAppId;
  if (appId == null) return null;
  final json = await _apiGet(client, key, '/games/steam/$appId');
  final data = json['data'];
  if (data is Map && data['id'] is num) {
    return (data['id'] as num).toInt();
  }
  return null;
}

Future<void> _downloadBestAsset({
  required HttpClient client,
  required String key,
  required String kind,
  required int sgdbId,
  required File outFile,
  required bool force,
  required String query,
  List<String> preferFormats = const ['.png', '.jpg', '.jpeg', '.webp'],
}) async {
  final json = await _apiGet(client, key, '/$kind/game/$sgdbId?$query');
  final data = json['data'];
  if (data is! List || data.isEmpty) {
    stderr.writeln('  $kind: 无结果');
    return;
  }
  final sorted = List<Map<String, dynamic>>.from(
    data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
  );
  sorted.sort((a, b) {
    final sa = (a['score'] as num?)?.toInt() ?? 0;
    final sb = (b['score'] as num?)?.toInt() ?? 0;
    return sb.compareTo(sa);
  });

  Map<String, dynamic>? chosen;
  for (final item in sorted) {
    final url = item['url']?.toString() ?? '';
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final mime = '${item['mime'] ?? ''}'.toLowerCase();
    final okExt = preferFormats.any(path.endsWith);
    final okMime = mime.contains('png') ||
        mime.contains('jpeg') ||
        mime.contains('jpg') ||
        mime.contains('webp');
    // 跳过 ICO（Flutter Image.asset 不支持）
    if (path.endsWith('.ico') || mime.contains('icon')) continue;
    if (okExt || okMime || preferFormats.isEmpty) {
      chosen = item;
      break;
    }
  }
  chosen ??= sorted.cast<Map<String, dynamic>?>().firstWhere(
        (item) {
          final url = item?['url']?.toString() ?? '';
          return !url.toLowerCase().endsWith('.ico');
        },
        orElse: () => null,
      );

  if (chosen == null) {
    stderr.writeln('  $kind: 无可用 PNG/JPEG（仅有 ICO），跳过');
    return;
  }

  final url = chosen['url']?.toString();
  if (url == null || url.isEmpty) {
    stderr.writeln('  $kind: 无 url');
    return;
  }

  var target = outFile;
  final uriPath = Uri.parse(url).path.toLowerCase();
  if (uriPath.endsWith('.webp')) {
    target = File(outFile.path.replaceAll(RegExp(r'\.[^.]+$'), '.webp'));
  } else if (uriPath.endsWith('.jpg') || uriPath.endsWith('.jpeg')) {
    target = File(outFile.path.replaceAll(RegExp(r'\.[^.]+$'), '.jpg'));
  } else if (uriPath.endsWith('.png')) {
    target = File(outFile.path.replaceAll(RegExp(r'\.[^.]+$'), '.png'));
  }

  if (target.existsSync() && !force) {
    stdout.writeln('  skip $kind (已存在 ${target.path})');
    return;
  }

  stdout.writeln('  $kind ← $url');
  final bytes = await _downloadBytes(client, url);
  await target.writeAsBytes(bytes, flush: true);
  // 清理同 stem 的旧扩展名
  final stem = outFile.path.replaceAll(RegExp(r'\.[^.]+$'), '');
  for (final ext in ['.png', '.jpg', '.jpeg', '.webp', '.ico']) {
    final other = File('$stem$ext');
    if (other.path != target.path && other.existsSync()) {
      await other.delete();
    }
  }
  if (target.path != outFile.path) {
    stdout.writeln('  实际保存为 ${target.uri.pathSegments.last}，请同步 catalog 路径');
  } else {
    stdout.writeln('  写入 ${target.path}');
  }
}

Future<Map<String, dynamic>> _apiGet(
  HttpClient client,
  String key,
  String path,
) async {
  final uri = Uri.parse('$_apiBase$path');
  final req = await client.getUrl(uri);
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
  req.headers.set(HttpHeaders.acceptHeader, 'application/json');
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw HttpException('API ${res.statusCode} $path: $body', uri: uri);
  }
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('非 JSON 对象: $path');
  }
  if (decoded['success'] == false) {
    throw StateError('API success=false $path: $body');
  }
  return decoded;
}

Future<List<int>> _downloadBytes(HttpClient client, String url) async {
  final uri = Uri.parse(url);
  final req = await client.getUrl(uri);
  req.headers.set(HttpHeaders.userAgentHeader, 'AstralGame-cover-fetch/1.0');
  final res = await req.close();
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw HttpException('下载失败 ${res.statusCode}', uri: uri);
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in res) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
