import 'dart:convert';
import 'dart:io';

import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/room_persistence_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path_lib;

RoomInvitePayload _payload(String tag) => RoomInvitePayload(
      gameId: 'stardew',
      gameName: '星露谷',
      networkName: 'net-$tag',
      networkSecret: 'secret-$tag',
      peers: [const PeerEndpoint(uri: 'tcp://1.2.3.4:1234')],
    );

void main() {
  late Directory tmpDir;
  late RoomPersistenceService persistence;
  late RoomState roomState;
  late String jsonPath;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('room_state_test');
    persistence = RoomPersistenceService(directoryPath: tmpDir.path);
    roomState = RoomState();
    roomState.initPersistence(persistence);
    jsonPath = path_lib.join(tmpDir.path, 'bookmarks.json');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('并发 quickSaveBookmark：两条都落盘不互相覆盖（lost update 回归）', () async {
    // 不 await 第一个，模拟真实调用点的 fire-and-forget
    final f1 = roomState.quickSaveBookmark(_payload('a'));
    final f2 = roomState.quickSaveBookmark(_payload('b'));
    await Future.wait([f1, f2]);

    expect(roomState.bookmarks.length, 2);
    final onDisk = jsonDecode(File(jsonPath).readAsStringSync()) as List;
    expect(onDisk.length, 2, reason: '写队列应串行落盘两条');
  });

  test('touchUsed 与 quickSave 并发：lastUsedAt 与新收藏都保留', () async {
    final saved = await roomState.quickSaveBookmark(_payload('a'));
    // 加入房间场景：touchBookmarkUsed（fire-and-forget）与再次收藏并发
    final f1 = roomState.touchBookmarkUsed(saved.id);
    final f2 = roomState.quickSaveBookmark(_payload('b'));
    await Future.wait([f1, f2]);

    expect(roomState.bookmarks.length, 2);
    final touched =
        roomState.bookmarks.firstWhere((b) => b.id == saved.id);
    expect(touched.lastUsedAt, isNotNull, reason: 'touchUsed 不应被 quickSave 覆盖掉');
  });

  test('removeBookmark 与 quickSave 并发：删除生效且新收藏保留', () async {
    final saved = await roomState.quickSaveBookmark(_payload('a'));
    final f1 = roomState.removeBookmark(saved.id);
    final f2 = roomState.quickSaveBookmark(_payload('b'));
    await Future.wait([f1, f2]);

    expect(roomState.bookmarks.length, 1);
    expect(roomState.bookmarks.first.payload.networkName, 'net-b',
        reason: '删除不应被并发的保存"复活"，新收藏也不应被吞');
  });

  test('连续快速收藏：id 互不相同', () async {
    final ids = <int>[];
    for (var i = 0; i < 20; i++) {
      final b = await roomState.quickSaveBookmark(_payload('p$i'));
      ids.add(b.id);
    }
    expect(ids.toSet().length, 20, reason: 'id 应严格唯一');
  });
}
