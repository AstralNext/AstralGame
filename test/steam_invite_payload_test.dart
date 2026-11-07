import 'dart:convert';

import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:flutter_test/flutter_test.dart';

RoomInvitePayload _steamPayload() => const RoomInvitePayload(
  gameId: 'scfa',
  gameName: '最高指挥官',
  networkName: 'ag_abcdefghij',
  networkSecret: '0123456789ABCDEF',
  peers: <PeerEndpoint>[],
  displayName: '老王的车队',
  transport: 'steam',
  hostSteamId: '76561198000000001',
);

void main() {
  group('Steam 邀请载荷', () {
    test('离线邀请往返保留 transport 与 host_steam_id', () {
      final encoded = encodeOfflineInvite(_steamPayload());
      final decoded = decodeOfflineInvite(encoded);

      expect(decoded.isSteamTransport, isTrue);
      expect(decoded.hostSteamId, '76561198000000001');
      expect(decoded.networkSecret, '0123456789ABCDEF');
      expect(decoded.gameId, 'scfa');
      expect(decoded.displayName, '老王的车队');
    });

    test('JSON 字段名与短码服务契约一致', () {
      final json = _steamPayload().toJson();

      expect(json['transport'], 'steam');
      expect(json['host_steam_id'], '76561198000000001');
      expect(json['game_id'], 'scfa');
      expect(json['network_secret'], '0123456789ABCDEF');

      final restored = RoomInvitePayload.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(restored.isSteamTransport, isTrue);
      expect(restored.hostSteamId, '76561198000000001');
    });

    test('缺少 host_steam_id 的 Steam 邀请能被识别为缺字段', () {
      final json = _steamPayload().toJson()..remove('host_steam_id');
      final decoded = RoomInvitePayload.fromJson(json);

      expect(decoded.isSteamTransport, isTrue);
      expect(decoded.hostSteamId, isNull);
    });

    test('未携带 transport 的旧邀请仍按 EasyTier 处理', () {
      final json = _steamPayload().toJson()..remove('transport');
      final decoded = RoomInvitePayload.fromJson(json);

      expect(decoded.isSteamTransport, isFalse);
    });
  });

  group('joinableInvitePeers', () {
    test('Steam 房间允许没有 peers（靠 hostSteamId 直连）', () {
      expect(joinableInvitePeers(_steamPayload()), isEmpty);
    });

    test('EasyTier 房间缺少 peers 时明确报错', () {
      const payload = RoomInvitePayload(
        gameId: 'scfa',
        gameName: '最高指挥官',
        networkName: 'ag_abcdefghij',
        networkSecret: 'secret',
        peers: <PeerEndpoint>[],
      );

      expect(() => joinableInvitePeers(payload), throwsStateError);
    });
  });

  group('离线邀请校验', () {
    test('缺少房间口令时拒绝解析', () {
      final json = _steamPayload().toJson()..['network_secret'] = '';
      final encoded =
          '$kOfflineInvitePrefix${base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '')}';

      expect(() => decodeOfflineInvite(encoded), throwsFormatException);
    });
  });
}
