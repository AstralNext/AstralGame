import 'dart:io';

import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

const _probeJson = '''
{"version": 99, "games": [
  {"id": "cache_probe", "name": "Cache Probe", "color": "#111111", "icon": "games"}
]}
''';

void main() {
  late Directory cacheDir;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('astral-rules-cache-');
  });

  tearDown(() async {
    if (cacheDir.existsSync()) {
      await cacheDir.delete(recursive: true);
    }
  });

  test('200 response is written to disk cache', () async {
    final client = MockClient((_) async {
      return http.Response(
        _probeJson,
        200,
        headers: {'etag': '"v1"'},
      );
    });
    final svc = GameAssistRulesService(
      client: client,
      testRuleDirs: const [],
      cacheDir: cacheDir,
    );
    addTearDown(svc.close);
    final catalog = await svc.ensureLoaded();
    expect(catalog.byId('cache_probe'), isNotNull);
    expect(
      File(p.join(cacheDir.path, 'gamerules-cache.json')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(cacheDir.path, 'gamerules-cache.etag')).readAsStringSync(),
      '"v1"',
    );
  });

  test('sends If-None-Match and keeps cache on 304', () async {
    final etagFile = File(p.join(cacheDir.path, 'gamerules-cache.etag'));
    await File(p.join(cacheDir.path, 'gamerules-cache.json'))
        .writeAsString(_probeJson);
    await etagFile.writeAsString('"v1"');

    String? ifNoneMatch;
    final client = MockClient((req) async {
      ifNoneMatch = req.headers['if-none-match'];
      return http.Response('', 304);
    });
    final svc = GameAssistRulesService(
      client: client,
      testRuleDirs: const [],
      cacheDir: cacheDir,
    );
    addTearDown(svc.close);
    final catalog = await svc.ensureLoaded();
    expect(ifNoneMatch, '"v1"');
    expect(catalog.byId('cache_probe'), isNotNull);
  });

  test('uses disk cache when remote fails', () async {
    await File(p.join(cacheDir.path, 'gamerules-cache.json'))
        .writeAsString(_probeJson);
    final client = MockClient((_) async {
      throw const SocketException('offline');
    });
    final svc = GameAssistRulesService(
      client: client,
      testRuleDirs: const [],
      cacheDir: cacheDir,
    );
    addTearDown(svc.close);
    final catalog = await svc.ensureLoaded();
    expect(catalog.byId('cache_probe'), isNotNull);
  });

  test('test dir catalog skips remote fetch', () async {
    var remoteHits = 0;
    final client = MockClient((_) async {
      remoteHits++;
      return http.Response('no', 500);
    });
    final dir = await Directory.systemTemp.createTemp('astral-rules-test-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    await File(p.join(dir.path, 'gamerules.json')).writeAsString(
      '{"version": 1, "games": ['
      '{"id": "from_test", "name": "From Test", "color": "#000000", "icon": "games"}'
      ']}',
    );
    final svc = GameAssistRulesService(
      client: client,
      testRuleDirs: [dir],
      cacheDir: cacheDir,
    );
    addTearDown(svc.close);
    final catalog = await svc.ensureLoaded();
    expect(catalog.byId('from_test'), isNotNull);
    expect(remoteHits, 0);
  });

  test('falls back to asset when remote and cache fail', () async {
    const assetJson =
        '{"version": 1, "games": [{"id": "minecraft", "name": "Minecraft", "color": "#111111", "icon": "games"}]}';
    final client = MockClient((_) async {
      throw const SocketException('offline');
    });
    final svc = GameAssistRulesService(
      client: client,
      testRuleDirs: const [],
      cacheDir: cacheDir,
      assetLoader: () async => assetJson,
    );
    addTearDown(svc.close);
    final catalog = await svc.ensureLoaded();
    expect(catalog.byId('minecraft'), isNotNull);
  });
}
