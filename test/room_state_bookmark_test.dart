import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/bookmark_store.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存实现：只服务 RoomState 的写队列语义验证，不拉起真正的 Isar。
class _MemoryBookmarkStore implements BookmarkStore {
  final Map<int, Bookmark> items = {};

  @override
  Future<List<Bookmark>> loadAll() async =>
      items.values.toList()..sort(compareBookmarks);

  @override
  Future<void> save(Bookmark bookmark) async => items[bookmark.id] = bookmark;

  @override
  Future<void> deleteById(int id) async => items.remove(id);

  @override
  Future<void> touchUsed(int id, DateTime at) async {
    final existing = items[id];
    if (existing != null) items[id] = existing.copyWith(lastUsedAt: at);
  }
}

RoomInvitePayload _payload(String tag) => RoomInvitePayload(
  gameId: 'stardew',
  gameName: '星露谷',
  networkName: 'net-$tag',
  networkSecret: 'secret-$tag',
  peers: [const PeerEndpoint(uri: 'tcp://1.2.3.4:1234')],
);

void main() {
  late _MemoryBookmarkStore store;
  late RoomState roomState;

  setUp(() {
    store = _MemoryBookmarkStore();
    roomState = RoomState();
    roomState.initPersistence(store);
  });

  test('并发 quickSaveBookmark：两条都入库不互相覆盖（lost update 回归）', () async {
    // 不 await 第一个，模拟真实调用点的 fire-and-forget
    final f1 = roomState.quickSaveBookmark(_payload('a'));
    final f2 = roomState.quickSaveBookmark(_payload('b'));
    await Future.wait([f1, f2]);

    expect(roomState.bookmarks.length, 2);
    expect(store.items.length, 2, reason: '写队列应串行落库两条');
  });

  test('touchUsed 与 quickSave 并发：lastUsedAt 与新收藏都保留', () async {
    final saved = await roomState.quickSaveBookmark(_payload('a'));
    // 加入房间场景：touchBookmarkUsed（fire-and-forget）与再次收藏并发
    final f1 = roomState.touchBookmarkUsed(saved.id);
    final f2 = roomState.quickSaveBookmark(_payload('b'));
    await Future.wait([f1, f2]);

    expect(roomState.bookmarks.length, 2);
    final touched = roomState.bookmarks.firstWhere((b) => b.id == saved.id);
    expect(
      touched.lastUsedAt,
      isNotNull,
      reason: 'touchUsed 不应被 quickSave 覆盖掉',
    );
    expect(
      store.items[saved.id]?.lastUsedAt,
      isNotNull,
      reason: 'lastUsedAt 也要落到 store',
    );
  });

  test('removeBookmark 与 quickSave 并发：删除生效且新收藏保留', () async {
    final saved = await roomState.quickSaveBookmark(_payload('a'));
    final f1 = roomState.removeBookmark(saved.id);
    final f2 = roomState.quickSaveBookmark(_payload('b'));
    await Future.wait([f1, f2]);

    expect(roomState.bookmarks.length, 1);
    expect(
      roomState.bookmarks.first.payload.networkName,
      'net-b',
      reason: '删除不应被并发的保存"复活"，新收藏也不应被吞',
    );
    expect(store.items.containsKey(saved.id), isFalse, reason: 'store 里也要删掉');
  });

  test('连续快速收藏：id 互不相同', () async {
    final ids = <int>[];
    for (var i = 0; i < 20; i++) {
      final b = await roomState.quickSaveBookmark(_payload('p$i'));
      ids.add(b.id);
    }
    expect(ids.toSet().length, 20, reason: 'id 应严格唯一');
  });

  test('loadFromPersistence：从 store 恢复，置顶项排在前', () async {
    await store.save(
      Bookmark(
        id: 1,
        customName: '新房间',
        payload: _payload('a'),
        savedAt: DateTime(2024, 5, 2),
      ),
    );
    await store.save(
      Bookmark(
        id: 2,
        customName: '置顶房间',
        payload: _payload('b'),
        savedAt: DateTime(2024, 1, 3),
        pinned: true,
      ),
    );

    await roomState.loadFromPersistence();

    expect(roomState.bookmarks.length, 2);
    expect(roomState.bookmarks.first.customName, '置顶房间');
  });
}
