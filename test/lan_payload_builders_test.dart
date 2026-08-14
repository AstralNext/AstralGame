import 'dart:convert';
import 'dart:typed_data';

import 'package:astral_game/data/services/lan_payload_builders.dart';
import 'package:astral_game/data/services/lan_payload_parsers.dart';
import 'package:astral_game/data/services/scfa_discovery_beacon.dart';
import 'package:astral_game/data/services/scfa_lan_codec.dart';
import 'package:astral_game/utils/lan_title_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('title template player + game', () {
    expect(
      applyLanTitleTemplate(
        '{player} · {game}',
        player: '二哈',
        game: 'Minecraft',
        motd: 'My World',
      ),
      '二哈 · Minecraft',
    );
  });

  test('title template includes map', () {
    expect(
      applyLanTitleTemplate(
        '{player} * Astral',
        player: 'a',
        game: 'Forged Alliance',
        map: 'Four-Corners',
      ),
      'a * Astral',
    );
  });

  test('scfa_lan roundtrip loud probe', () {
    final bytes = buildScfaLanReply(
      requestKind: 0x8C,
      title: 'a * Astral',
      lobbyPort: 58336,
      hostedBy: 'a',
      mapName: 'Four-Corners',
      address: '10.126.126.1',
    );
    expect(bytes, isNotNull);
    expect(bytes![0], 0x8D);
    final parsed = parseScfaLanReply(bytes, fallbackPort: 0);
    expect(parsed, isNotNull);
    expect(parsed!.lobbyPort, 58336);
    expect(parsed.gameName, 'a * Astral');
    expect(parsed.hostedBy, 'a');
    expect(parsed.mapName, 'Four-Corners');
    expect(parsed.scenarioFile, '/maps/scmp_039/scmp_039_scenario.lua');
    expect(parsed.address, '10.126.126.1');
    expect(String.fromCharCodes(bytes), contains('AllowObservers'));
    final hit = parseScfaLanPayload(bytes, fallbackPort: 0);
    expect(hit?.port, 58336);
    expect(hit?.motd, 'Four-Corners');
  });

  test('scfa remote announce prefers local UDP forward port', () {
    final proxied = scfaAnnounceForRemote(
      title: 'a * Astral',
      hostedBy: 'host',
      mapName: 'Four-Corners',
      remotePort: 8888,
      remoteIpv4: '10.126.126.2',
      localUdpPort: 54321,
    );
    expect(proxied.lobbyPort, 54321);
    expect(proxied.ipv4, scfaLanProxyReplyIp);

    final direct = scfaAnnounceForRemote(
      title: 'a * Astral',
      hostedBy: 'host',
      remotePort: 8888,
      remoteIpv4: '10.126.126.2',
    );
    expect(direct.lobbyPort, 8888);
    expect(direct.ipv4, '10.126.126.2');
  });

  test('raft_lan announce', () {
    final name = utf8.encode('二哈 · World');
    final bytes = Uint8List(19 + name.length);
    final bd = ByteData.sublistView(bytes);
    bd.setUint32(0, 0x41535452, Endian.little);
    bytes[4] = 1;
    bytes[5] = 10;
    bd.setUint64(6, 76561198000000000, Endian.little);
    bd.setUint16(14, 6488, Endian.little);
    bytes[16] = 0;
    bd.setUint16(17, name.length, Endian.little);
    bytes.setRange(19, 19 + name.length, name);
    final hit = parseRaftLanPayload(bytes, fallbackPort: 6489);
    expect(hit?.port, 6488);
    expect(hit?.label, '二哈 · World');
  });

  test('minecraft_motd rebuild', () {
    final bytes = buildMinecraftMotdPayload(title: '二哈 · Minecraft', port: 25565);
    expect(bytes, isNotNull);
    expect(
      utf8.decode(bytes!),
      '[MOTD]二哈 · Minecraft[/MOTD][AD]25565[/AD]',
    );
  });
}
