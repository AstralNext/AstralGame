import 'dart:convert';
import 'dart:io';

import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/room_persistence_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_lib;

Bookmark _bookmark(int id, {String name = '房间'}) {
  final now = DateTime.now();
  return Bookmark(
    id: id,
    customName: name,
    payload: RoomInvitePayload(
      gameId: 'stardew',
      gameName: '星露谷',
      networkName: 'net-$id',
      networkSecret: 'secret-$id',
      peers: [const PeerEndpoint(uri: 'tcp://1.2.3.4:1234')],
    ),
    savedAt: now,
  );
}

void main() {
  late Directory tmpDir;
  late RoomPersistenceService service;
  late String jsonPath;
  late String bakPath;
  late String tmpPath;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('bookmarks_test');
    service = RoomPersistenceService(directoryPath: tmpDir.path);
    jsonPath = path_lib.join(tmpDir.path, 'bookmarks.json');
    bakPath = '$jsonPath.bak';
    tmpPath = '$jsonPath.tmp';
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  group('正常读写', () {
    test('保存后能加载回同 id 同名收藏', () async {
      await service.saveBookmarks([_bookmark(1), _bookmark(2, name: 'B局')]);
      final loaded = await service.loadBookmarks();
      expect(loaded.length, 2);
      expect(loaded.map((b) => b.id), containsAll([1, 2]));
    });

    test('保存使用原子写：不留 .tmp 残留，且生成 .bak', () async {
      await service.saveBookmarks([_bookmark(1)]);
      await service.saveBookmarks([_bookmark(1), _bookmark(2)]);
      expect(File(tmpPath).existsSync(), isFalse,
          reason: 'tmp 文件应在 rename 后消失');
      expect(File(bakPath).existsSync(), isTrue,
          reason: '第二次保存前应把旧文件备份为 .bak');
      // .bak 内容是上一次保存的状态（1 条）
      final bakContent = jsonDecode(File(bakPath).readAsStringSync());
      expect(bakContent, isA<List>().having((l) => l.length, 'length', 1));
    });

    test('空文件视为合法空列表，不触发损坏恢复', () async {
      // 用户主动清空所有收藏 → json 变成 []，bak 保留上一版
      await service.saveBookmarks([_bookmark(1)]);
      await service.saveBookmarks([]);
      final loaded = await service.loadBookmarks();
      expect(loaded, isEmpty,
          reason: '空列表是用户主动清空的合法状态');
      expect(File(jsonPath).readAsStringSync(), '[]',
          reason: '不能用 .bak 里的一条旧数据"复活"用户已清空的收藏');
      expect(File(bakPath).existsSync(), isTrue);
    });
  });

  group('损坏自愈', () {
    test('json 半截损坏时从 .bak 恢复到上一次保存的状态', () async {
      await service.saveBookmarks([_bookmark(1)]);
      await service.saveBookmarks([_bookmark(1), _bookmark(2, name: 'B局')]);
      // 第三次保存让 .bak 升级为 2 条版本
      await service.saveBookmarks([_bookmark(1), _bookmark(2, name: 'B局'), _bookmark(3, name: 'C局')]);
      // 模拟进程写入中途被杀：留下半截 JSON
      final good = File(jsonPath).readAsStringSync();
      File(jsonPath).writeAsStringSync(good.substring(0, good.length ~/ 2));

      final loaded = await service.loadBookmarks();
      // .bak 是上一次成功保存的快照（2 条版本）
      expect(loaded.length, 2, reason: '应从 .bak 恢复出上一次保存的 2 条');
      expect(loaded.map((b) => b.id), containsAll([1, 2]));
      // 正式文件应已被恢复为合法 JSON
      final restored = jsonDecode(File(jsonPath).readAsStringSync());
      expect(restored, isA<List>().having((l) => l.length, 'length', 2));
    });

    test('json 损坏且无 .bak 时：隔离为 .corrupt-* 留证，不静默清空覆盖', () async {
      File(jsonPath).writeAsStringSync('{"corrupted": tru');
      final loaded = await service.loadBookmarks();
      expect(loaded, isEmpty);
      final corruptFiles = tmpDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt-'))
          .toList();
      expect(corruptFiles, isNotEmpty,
          reason: '损坏文件应被改名隔离，供手动抢救');
      expect(File(jsonPath).existsSync(), isFalse);
    });

    test('.bak 也损坏时放弃恢复，隔离两个坏文件', () async {
      await service.saveBookmarks([_bookmark(1)]);
      File(jsonPath).writeAsStringSync('[{"broken"');
      File(bakPath).writeAsStringSync('[{"also broken"');
      final loaded = await service.loadBookmarks();
      expect(loaded, isEmpty);
      final corruptCount = tmpDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.corrupt-'))
          .length;
      expect(corruptCount, greaterThanOrEqualTo(1));
    });
  });

  group('孤儿暂存（schema 不兼容防丢）', () {
    test('单条解析失败不丢弃：孤儿在下次保存时原样写回文件', () async {
      await service.saveBookmarks([_bookmark(1)]);
      // 手工构造一条"未来字段损坏"的条目追加进文件（模拟升级后旧数据解析失败）
      final list = jsonDecode(File(jsonPath).readAsStringSync()) as List;
      list.add({
        'id': 999,
        'customName': '旧版本数据',
        'payload': {'v': 1}, // 缺少 required 字段 → fromJson 抛错
        'savedAt': '2024-01-01T00:00:00.000',
      });
      File(jsonPath).writeAsStringSync(jsonEncode(list));

      final loaded = await service.loadBookmarks();
      expect(loaded.length, 1, reason: '只有 1 条能解析');

      // 触发一次保存（例如用户改置顶）：孤儿必须被写回而不是被清掉
      await service.saveBookmarks(loaded);

      final after = jsonDecode(File(jsonPath).readAsStringSync()) as List;
      expect(after.length, 2, reason: '孤儿条目应原样保留在文件里');
      final orphan = after.firstWhere((e) => e['id'] == 999);
      expect(orphan['customName'], '旧版本数据');
    });

    test('孤儿与新收藏共存：新增收藏不会挤掉孤儿', () async {
      await service.saveBookmarks([_bookmark(1)]);
      final list = jsonDecode(File(jsonPath).readAsStringSync()) as List;
      list.add({
        'id': 999,
        'customName': '孤儿',
        'payload': '不是对象',
      });
      File(jsonPath).writeAsStringSync(jsonEncode(list));

      await service.loadBookmarks();
      await service.upsert(await service.loadBookmarks(), _bookmark(2));

      final after = jsonDecode(File(jsonPath).readAsStringSync()) as List;
      expect(after.length, 3, reason: '旧1条 + 新1条 + 孤儿1条');
    });
  });

}
