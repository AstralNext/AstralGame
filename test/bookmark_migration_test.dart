import 'dart:convert';
import 'dart:io';

import 'package:astral_game/data/services/bookmark_store.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _entry(int id, String name) => {
      'id': id,
      'customName': name,
      'payload': {
        'game_id': 'stardew',
        'game_name': '星露谷',
        'network_name': 'net-$id',
        'network_secret': 'secret-$id',
        'peers': [
          {'uri': 'tcp://1.2.3.4:1234'},
        ],
      },
      'savedAt': '2024-01-01T00:00:00.000',
    };

void main() {
  group('旧版 bookmarks.json 解析', () {
    test('正常数组：逐条解析', () {
      final parsed =
          parseLegacyBookmarksJson(jsonEncode([_entry(1, 'A局'), _entry(2, 'B局')]));
      expect(parsed?.length, 2);
      expect(parsed?.map((b) => b.customName), containsAll(['A局', 'B局']));
    });

    test('空文件视为空列表（用户主动清空是合法状态）', () {
      expect(parseLegacyBookmarksJson('   '), isEmpty);
    });

    test('JSON 非法返回 null（整体不可用，交给 .bak 兜底）', () {
      expect(parseLegacyBookmarksJson('[{"broken"'), isNull);
    });

    test('顶层不是数组返回 null', () {
      expect(parseLegacyBookmarksJson('{"a":1}'), isNull);
    });

    test('单条字段不兼容只跳过该条，不牵连其余', () {
      final broken = {'id': 2, 'payload': {'v': 1}};
      final parsed =
          parseLegacyBookmarksJson(jsonEncode([_entry(1, '好'), broken]));
      expect(parsed?.length, 1);
      expect(parsed?.first.id, 1);
    });
  });

  group('readLegacyBookmarks 读取与 .bak 回退', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('legacy_bookmarks_test');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('主文件正常时直接读取', () async {
      final file = File('${dir.path}/bookmarks.json')
        ..writeAsStringSync(jsonEncode([_entry(1, 'A局')]));
      expect((await readLegacyBookmarks(file)).length, 1);
    });

    test('主文件损坏时回退到 .bak', () async {
      final file = File('${dir.path}/bookmarks.json')
        ..writeAsStringSync('[{"broken"');
      File('${file.path}.bak')
          .writeAsStringSync(jsonEncode([_entry(1, 'A局'), _entry(2, 'B局')]));

      final loaded = await readLegacyBookmarks(file);
      expect(loaded.length, 2, reason: '应从 .bak 抢救出上一次的完整快照');
    });

    test('主文件与 .bak 都不可用时返回空，不抛异常', () async {
      final file = File('${dir.path}/bookmarks.json')
        ..writeAsStringSync('[{"broken"');
      File('${file.path}.bak').writeAsStringSync('[{"also broken"');
      expect(await readLegacyBookmarks(file), isEmpty);
    });
  });
}
