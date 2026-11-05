import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/bookmark_record.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:flutter_test/flutter_test.dart';

const _pearKey =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

RoomInvitePayload _pearPayload() => const RoomInvitePayload(
      gameId: 'stardew',
      gameName: '星露谷',
      networkName: 'pear-net',
      networkSecret: 'pear-secret',
      peers: [PeerEndpoint(uri: 'tcp://1.2.3.4:1234')],
      displayName: 'Pear 局',
      transport: 'pear',
      hostPearKey: _pearKey,
    );

void main() {
  group('收藏记录保留传输方式', () {
    test('Pear 房主公钥经过 Isar 记录往返后不丢失', () {
      final bookmark = Bookmark(
        id: 42,
        customName: 'Pear 局',
        payload: _pearPayload(),
        savedAt: DateTime(2026),
      );

      final restored = toBookmark(toRecord(bookmark));
      expect(restored.payload.transport, 'pear');
      expect(restored.payload.isPearTransport, isTrue);
      expect(restored.payload.hostPearKey, _pearKey);
    });

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
      expect(restored.payload.isPearTransport, isFalse);
    });
  });

  test('Pear 离线邀请编解码保留 transport 与 hostPearKey', () {
    final encoded = encodeOfflineInvite(_pearPayload());
    final decoded = decodeOfflineInvite(encoded);
    expect(decoded.transport, 'pear');
    expect(decoded.hostPearKey, _pearKey);
  });
}
