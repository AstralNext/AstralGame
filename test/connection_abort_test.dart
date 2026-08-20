import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('abort invalidates in-flight epoch', () {
    final link = ConnectionLinkEpoch();
    final epoch = link.begin();
    expect(link.isLive(epoch), isTrue);

    link.abort();
    expect(link.isLive(epoch), isFalse);
    expect(link.current, epoch + 1);
  });

  test('new begin after abort is live', () {
    final link = ConnectionLinkEpoch();
    final first = link.begin();
    link.abort();
    final second = link.begin();
    expect(link.isLive(first), isFalse);
    expect(link.isLive(second), isTrue);
  });

  test('joinableInvitePeers rejects empty secret or empty uris', () {
    expect(
      () => joinableInvitePeers(
        const RoomInvitePayload(
          gameId: 'minecraft',
          gameName: 'Minecraft',
          networkName: 'room',
          networkSecret: '',
          peers: [PeerEndpoint(uri: 'tcp://1.1.1.1:11010')],
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => joinableInvitePeers(
        const RoomInvitePayload(
          gameId: 'minecraft',
          gameName: 'Minecraft',
          networkName: 'room',
          networkSecret: 'secret',
          peers: [PeerEndpoint(uri: '  ')],
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('joinableInvitePeers keeps non-empty peer uris', () {
    final peers = joinableInvitePeers(
      const RoomInvitePayload(
        gameId: 'minecraft',
        gameName: 'Minecraft',
        networkName: 'room',
        networkSecret: 'secret',
        peers: [
          PeerEndpoint(uri: ''),
          PeerEndpoint(uri: 'tcp://1.1.1.1:11010'),
        ],
      ),
    );
    expect(peers, hasLength(1));
    expect(peers.single.uri, 'tcp://1.1.1.1:11010');
  });
}
