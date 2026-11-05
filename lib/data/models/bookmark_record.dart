import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:isar_community/isar.dart';

part 'bookmark_record.g.dart';

/// 收藏房间的 Isar 集合。
///
/// 主键直接复用业务 [Bookmark.id]（毫秒时间戳×1000+随机数，恒为正），
/// 因此 `put` 本身就是"按 id upsert"，不再需要"读整表 → 改 → 写整表"。
///
/// Isar 的集合类不能是 freezed 生成的不可变类，故另建本记录类，
/// 由 [toRecord] / [toBookmark] 与领域模型互转。
@collection
class BookmarkRecord {
  Id id = Isar.autoIncrement;

  String customName = '';
  RoomInvitePayloadRecord payload = RoomInvitePayloadRecord();
  DateTime savedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? lastUsedAt;
  bool pinned = false;
}

/// [RoomInvitePayload] 的 Isar 内嵌副本。
@embedded
class RoomInvitePayloadRecord {
  int v = 1;
  String gameId = '';
  String gameName = '';
  String networkName = '';
  String networkSecret = '';
  String? displayName;
  List<PeerEndpointRecord> peers = [];

  /// 传输方式（`easytier` / `steam` / `pear`）。旧记录读出来是空串，
  /// 由 [toBookmark] 归一化为 `easytier`。
  String transport = '';

  /// Steam 组网的房主 SteamID。
  String? hostSteamId;

  /// Pear 组网的房主 HyperDHT 公钥。
  String? hostPearKey;
}

/// [PeerEndpoint] 的 Isar 内嵌副本。
@embedded
class PeerEndpointRecord {
  String uri = '';
}

BookmarkRecord toRecord(Bookmark b) {
  final payload = RoomInvitePayloadRecord()
    ..v = b.payload.v
    ..gameId = b.payload.gameId
    ..gameName = b.payload.gameName
    ..networkName = b.payload.networkName
    ..networkSecret = b.payload.networkSecret
    ..displayName = b.payload.displayName
    ..transport = b.payload.transport
    ..hostSteamId = b.payload.hostSteamId
    ..hostPearKey = b.payload.hostPearKey
    ..peers = [
      for (final e in b.payload.peers) PeerEndpointRecord()..uri = e.uri,
    ];
  return BookmarkRecord()
    ..id = b.id
    ..customName = b.customName
    ..payload = payload
    ..savedAt = b.savedAt
    ..lastUsedAt = b.lastUsedAt
    ..pinned = b.pinned;
}

Bookmark toBookmark(BookmarkRecord r) => Bookmark(
      id: r.id,
      customName: r.customName,
      payload: RoomInvitePayload(
        v: r.payload.v,
        gameId: r.payload.gameId,
        gameName: r.payload.gameName,
        networkName: r.payload.networkName,
        networkSecret: r.payload.networkSecret,
        peers: [for (final e in r.payload.peers) PeerEndpoint(uri: e.uri)],
        displayName: r.payload.displayName,
        transport: r.payload.transport.trim().isEmpty
            ? 'easytier'
            : r.payload.transport,
        hostSteamId: r.payload.hostSteamId,
        hostPearKey: r.payload.hostPearKey,
      ),
      savedAt: r.savedAt,
      lastUsedAt: r.lastUsedAt,
      pinned: r.pinned,
    );
