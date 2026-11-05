import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/bookmark_record.dart';
import 'package:astral_game/data/models/transport_mode.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('收藏记录保留传输方式', () {
    test('Steam 房主 SteamID 经过 Isar 记录往返后不丢失', () {
      const payload = RoomInvitePayload(
        gameId: 'stardew',
        gameName: '星露谷',
        networkName: 'steam-net',
        networkSecret: 'steam-secret',
        peers: [],
        transport: 'steam',
        hostSteamId: '76561198000000000',
      );

      final restored = toBookmark(
        toRecord(
          Bookmark(
            id: 7,
            customName: 'Steam 局',
            payload: payload,
            savedAt: DateTime(2026),
          ),
        ),
      );
      expect(restored.payload.isSteamTransport, isTrue);
      expect(restored.payload.hostSteamId, '76561198000000000');
    });

    test('旧记录 transport 为空时归一化为 easytier', () {
      final record = BookmarkRecord()..customName = '旧收藏';
      final restored = toBookmark(record);
      expect(restored.payload.transport, 'easytier');
    });
  });

  group('持久化传输方式迁移', () {
    test('已移除的传输方式在设置、收藏与邀请中均回落为 steam', () {
      expect(transportModeFromStorage('pear'), TransportMode.steam);

      final record = BookmarkRecord()..customName = '旧收藏';
      record.payload.transport = 'pear';
      expect(toBookmark(record).payload.isSteamTransport, isTrue);

      const legacy = RoomInvitePayload(
        gameId: 'stardew',
        gameName: '星露谷',
        networkName: 'legacy-net',
        networkSecret: 'legacy-secret',
        peers: [],
        transport: 'pear',
      );
      final decoded = decodeOfflineInvite(encodeOfflineInvite(legacy));
      expect(decoded.isSteamTransport, isTrue);
    });
  });
}
