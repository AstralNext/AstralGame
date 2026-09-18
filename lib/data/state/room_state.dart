import 'dart:math';

import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/services/room_persistence_service.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:signals/signals_core.dart';

/// 房间会话状态；**不再有自动历史记录**，只暴露用户主动收藏的 bookmarks。
///
/// 收藏写安全设计：
/// - 所有写操作（含"查找后更新"类组合操作）经 [_enqueue] 串行排队执行，
///   消除并发"读内存 → 改 → 写盘"导致的丢更新（例如加入房间时 touchUsed 与
///   refreshBookmarkShareCode 同时触发）；
/// - 新收藏 id 由 [_newBookmarkId] 生成并查重，避免毫秒时间戳撞车顶掉旧收藏。
class RoomState {
  RoomPersistenceService? _persistence;

  final isConnected = signal<bool>(false);
  final session = signal<ActiveRoomSession?>(null);

  /// 强制结束提示（VPN 失败 / 房主离线等），UI 消费后应 [clearForceEndNotice]。
  final forceEndNotice = signal<String?>(null);

  /// 客人侧：房主当前是否在线（基于成员列表推断）。
  final hostOnline = signal<bool>(true);

  /// 全部收藏（已按 pinned + sortKey 排序）。UI 消费前可再搜索/分页。
  final bookmarksList = signal<List<Bookmark>>([]);
  final connectedRoomName = signal<String?>(null);

  final Random _random = Random();

  /// 写操作串行队列：后来者排队执行，保证"读 signal → 计算 → 写盘 → 回赋"不交错。
  Future<void> _writeQueue = Future<void>.value();

  /// 把 action 排到写队列尾执行；action 抛错不中断后续排队（调用方仍能感知错误）。
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  void initPersistence(RoomPersistenceService persistence) {
    _persistence = persistence;
    appLogger.i('[RoomState] initPersistence 完成');
  }

  Future<void> loadFromPersistence() {
    return _enqueue(() async {
      final persistence = _persistence;
      appLogger.i(
        '[RoomState] loadFromPersistence: persistence=${persistence != null}',
      );
      final list = await persistence?.loadBookmarks() ?? const <Bookmark>[];
      bookmarksList.value = list;
      appLogger.i('[RoomState] loadFromPersistence: 加载完成，共 ${list.length} 条');
    });
  }

  void setConnected(bool value, {bool clearSession = true}) {
    isConnected.value = value;
    if (!value) {
      if (clearSession) {
        session.value = null;
      }
      connectedRoomName.value = null;
      hostOnline.value = true;
    }
  }

  void setSession(ActiveRoomSession? value) {
    session.value = value;
    connectedRoomName.value = value?.networkName;
    if (value != null) {
      hostOnline.value = true;
    }
  }

  void setForceEndNotice(String? message) {
    forceEndNotice.value = message;
  }

  void clearForceEndNotice() {
    forceEndNotice.value = null;
  }

  void setHostOnline(bool value) {
    hostOnline.value = value;
  }

  // ---------------- Bookmark 操作 ----------------

  /// 新增或覆盖一条收藏；同步 signal 和持久化（排队执行）。
  Future<void> upsertBookmark(Bookmark bookmark) {
    return _enqueue(() => _upsertLocked(bookmark));
  }

  /// 一键收藏：自动命名（游戏名 → 房间名 → 网络名），重名自动加序号，不弹任何 UI。
  ///
  /// 不存短码：短码绑定当次房间、房主退出即作废；加入与分享时按需 create 新码。
  Future<Bookmark> quickSaveBookmark(RoomInvitePayload payload) {
    return _enqueue(() async {
      final name = uniqueBookmarkName(
        bookmarksList.value.map((b) => b.customName),
        autoBookmarkName(payload),
      );
      final now = DateTime.now();
      final bookmark = Bookmark(
        id: _newBookmarkId(),
        customName: name,
        payload: payload,
        savedAt: now,
      );
      await _upsertLocked(bookmark);
      return bookmark;
    });
  }

  Future<void> removeBookmark(int id) {
    return _enqueue(() async {
      final persistence = _persistence;
      final next = persistence == null
          ? bookmarksList.value.where((b) => b.id != id).toList()
          : await persistence.removeById(bookmarksList.value, id);
      bookmarksList.value = next;
    });
  }

  /// 用户从收藏点「加入」后：刷新 lastUsedAt（排队执行）。
  Future<void> touchBookmarkUsed(int id) {
    return _enqueue(() async {
      final persistence = _persistence;
      if (persistence == null) return;
      final next = await persistence.touchUsed(bookmarksList.value, id);
      bookmarksList.value = next;
    });
  }

  /// 查找给定 [payload] 是否已经被收藏（按 payload 内容哈希匹配）。
  Bookmark? findBookmarkForPayload(RoomInvitePayload payload) {
    final hash = hashInviteContent(payload);
    for (final b in bookmarksList.value) {
      if (b.contentHash == hash) return b;
    }
    return null;
  }

  /// 查找当前会话是否已被收藏。
  ///
  /// 优先用 [payload] 做完整哈希匹配（最准，游戏名+网络名+密码+服务器列表都对上）；
  /// 没有 payload 时 fallback 到 `networkName + secret`。
  Bookmark? findBookmarkForCurrentSession({RoomInvitePayload? payload}) {
    if (payload != null) return findBookmarkForPayload(payload);
    final s = session.value;
    if (s == null) return null;
    for (final b in bookmarksList.value) {
      if (b.payload.networkName == s.networkName &&
          b.payload.networkSecret == s.networkSecret) {
        return b;
      }
    }
    return null;
  }

  // ---------------- 内部实现 ----------------

  /// upsert 的实际执行体（须已在写队列内调用；不要在队列外直接调用，
  /// 否则会绕过串行化重新引入丢更新风险）。
  Future<void> _upsertLocked(Bookmark bookmark) async {
    final persistence = _persistence;
    appLogger.i(
      '[RoomState] upsertBookmark: id=${bookmark.id}, persistence=${persistence != null}',
    );
    final next = persistence == null
        ? ([bookmark, ...bookmarksList.value.where((b) => b.id != bookmark.id)]
          ..sort(RoomPersistenceService.compare))
        : await persistence.upsert(bookmarksList.value, bookmark);
    bookmarksList.value = next;
  }

  /// 新收藏 id：毫秒时间戳 × 1000 加随机数，并对现有列表查重重试，
  /// 防止同一毫秒连点或时钟回拨导致 id 撞车（upsert 会顶掉同 id 旧收藏）。
  int _newBookmarkId() {
    while (true) {
      final candidate =
          DateTime.now().millisecondsSinceEpoch * 1000 + _random.nextInt(1000);
      if (!bookmarksList.value.any((b) => b.id == candidate)) {
        return candidate;
      }
    }
  }

  // ---------------- UI 快捷访问 ----------------

  List<Bookmark> get bookmarks => bookmarksList.value;

  String? get activeShareCode => session.value?.shortCode;

  String? get activeRoomDisplayLabel {
    final s = session.value;
    if (s == null) return null;
    if (s.displayName.isNotEmpty) return s.displayName;
    return s.gameName.isNotEmpty ? s.gameName : s.networkName;
  }
}
