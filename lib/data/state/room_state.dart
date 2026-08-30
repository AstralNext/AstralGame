import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/services/room_persistence_service.dart';
import 'package:signals/signals_core.dart';

/// 房间会话状态；**不再有自动历史记录**，只暴露用户主动收藏的 bookmarks。
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

  void initPersistence(RoomPersistenceService persistence) {
    _persistence = persistence;
  }

  Future<void> loadFromPersistence() async {
    final list = await _persistence?.loadBookmarks() ?? const <Bookmark>[];
    bookmarksList.value = list;
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

  /// 新增或覆盖一条收藏；同步 signal 和持久化。
  Future<void> upsertBookmark(Bookmark bookmark) async {
    final persistence = _persistence;
    final next = persistence == null
        ? ([bookmark, ...bookmarksList.value.where((b) => b.id != bookmark.id)]
          ..sort(RoomPersistenceService.compare))
        : await persistence.upsert(bookmarksList.value, bookmark);
    bookmarksList.value = next;
  }

  Future<void> removeBookmark(int id) async {
    final persistence = _persistence;
    final next = persistence == null
        ? bookmarksList.value.where((b) => b.id != id).toList()
        : await persistence.removeById(bookmarksList.value, id);
    bookmarksList.value = next;
  }

  /// 用户从收藏点「加入」后：刷新 lastUsedAt。
  Future<void> touchBookmarkUsed(int id) async {
    final persistence = _persistence;
    final next = persistence == null
        ? bookmarksList.value
        : await persistence.touchUsed(bookmarksList.value, id);
    bookmarksList.value = next;
  }

  /// 查找给定 [payload] 是否已经被收藏（按 payload 内容哈希匹配）。
  Bookmark? findBookmarkForPayload(RoomInvitePayload payload) {
    final hash = hashInviteContent(payload);
    for (final b in bookmarksList.value) {
      if (b.contentHash == hash) return b;
    }
    return null;
  }

  /// 把刚自动 create 的短码回写到匹配的收藏里（加入房间那一刻拿到的短码，
  /// 之后在收藏页点分享就能直接复用了）。
  Future<void> refreshBookmarkShareCode(
    RoomInvitePayload payload, {
    required String shortCode,
    String? adminToken,
  }) async {
    final existing = findBookmarkForPayload(payload);
    if (existing == null) return;
    if (existing.originalShortCode?.trim() == shortCode) return;
    final updated = existing.copyWith(
      originalShortCode: shortCode,
      originalOfflineToken: adminToken ?? existing.originalOfflineToken,
    );
    await upsertBookmark(updated);
  }

  /// 查找当前会话是否已被收藏。
  ///
  /// - 优先用 [payload] 做完整哈希匹配（最准，游戏名+网络名+密码+服务器列表都对上）。
  /// - 没有 payload 时 fallback 到 `shortCode` 或 `networkName + secret`。
  Bookmark? findBookmarkForCurrentSession({RoomInvitePayload? payload}) {
    if (payload != null) return findBookmarkForPayload(payload);
    final s = session.value;
    if (s == null) return null;
    final short = s.shortCode?.trim();
    if (short != null && short.isNotEmpty) {
      for (final b in bookmarksList.value) {
        if (b.originalShortCode?.trim() == short) return b;
      }
    }
    for (final b in bookmarksList.value) {
      if (b.payload.networkName == s.networkName &&
          b.payload.networkSecret == s.networkSecret) {
        return b;
      }
    }
    return null;
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
