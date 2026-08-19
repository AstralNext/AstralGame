import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/services/lan_process_udp_discoverer.dart';
import 'package:astral_game/utils/net_addr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseHostPort splits ip:port', () {
    final a = parseHostPort('224.0.2.60:4445');
    expect(a?.host, '224.0.2.60');
    expect(a?.port, 4445);
  });

  test('lan_game_discover object', () {
    final cfg = GameAssistLanGameDiscoverConfig.tryParse({
      'type': 'udp_multicast',
      'multicast': '224.0.2.60:4445',
      'parser': 'minecraft_motd',
      'title': '{player} · {game}',
    });
    expect(cfg, isNotNull);
    expect(cfg!.entries, hasLength(1));
    final e = cfg.entries.first;
    expect(e.type, 'udp_multicast');
    expect(e.multicast, '224.0.2.60');
    expect(e.multicastPort, 4445);
    expect(e.parser, 'minecraft_motd');
    expect(e.title, '{player} · {game}');
    expect(e.id, 'udp_multicast');
  });

  test('lan_game_discover array', () {
    final cfg = GameAssistLanGameDiscoverConfig.tryParse([
      {'type': 'static_port', 'port': 24642},
      {
        'type': 'udp_probe',
        'probe': 'fe01',
        'parser': 'mindustry_server',
        'multicast': '227.2.7.7:20151',
        'port': 6567,
      },
    ]);
    expect(cfg!.entries, hasLength(2));
    expect(cfg.entries[0].port, 24642);
    expect(cfg.entries[1].probe, 'fe01');
    expect(cfg.entries[1].multicastPort, 20151);
  });

  test('udp_broadcast raft + mono inject', () {
    final cfg = GameAssistLanGameDiscoverConfig.tryParse({
      'id': 'raft_lan',
      'type': 'udp_broadcast',
      'port': 6489,
      'parser': 'raft_lan',
      'title': '{player} * Astral',
      'label': 'Raft',
    });
    expect(cfg, isNotNull);
    final e = cfg!.entries.single;
    expect(e.type, 'udp_broadcast');
    expect(e.port, 6489);
    expect(e.parser, 'raft_lan');

    final platform = GameAssistPlatformRules.fromJson({
      'inject': {
        'type': 'mono',
        'process': ['Raft.exe'],
        'dll': 'AstralRaftNet.dll',
        'namespace': 'AstralRaftNet',
        'class': 'Loader',
        'method': 'Init',
      },
    });
    expect(platform.inject?.isMono, isTrue);
    expect(platform.inject?.process, ['Raft.exe']);
    expect(platform.inject?.className, 'Loader');
  });

  test('udp_broadcast valheim + mono inject', () {
    final cfg = GameAssistLanGameDiscoverConfig.tryParse({
      'id': 'valheim_lan',
      'type': 'udp_broadcast',
      'port': 2460,
      'parser': 'valheim_lan',
      'title': '{player} * Astral',
      'label': 'Valheim',
    });
    expect(cfg!.entries.single.port, 2460);
    expect(cfg.entries.single.parser, 'valheim_lan');

    final platform = GameAssistPlatformRules.fromJson({
      'inject': {
        'type': 'mono',
        'process': ['valheim.exe'],
        'dll': 'AstralValheimNet.dll',
        'namespace': 'AstralValheimNet',
        'class': 'Loader',
        'method': 'Init',
        'delay_seconds': 8,
      },
    });
    expect(platform.inject?.isMono, isTrue);
    expect(platform.inject?.process, ['valheim.exe']);
    expect(platform.inject?.delaySeconds, 8);
  });

  test('remote catalog keeps local valheim inject', () {
    const local = GameAssistGameRules(
      id: 'valheim',
      name: 'Valheim',
      colorHex: '#4A6FA5',
      iconName: 'ac_unit',
      sort: 50,
      platforms: {
        'windows': GameAssistPlatformRules(
          magicWall: GameAssistMagicWallConfig.disabled,
          forwards: [],
          inject: GameAssistInjectConfig(
            type: 'mono',
            process: ['valheim.exe'],
            dll: 'AstralValheimNet.dll',
            namespace: 'AstralValheimNet',
            className: 'Loader',
          ),
        ),
      },
    );
    const remote = GameAssistGameRules(
      id: 'valheim',
      name: 'Valheim',
      colorHex: '#4A6FA5',
      iconName: 'ac_unit',
      sort: 50,
      platforms: {},
    );
    final merged = local.mergeFromRemote(remote);
    expect(merged.platforms['windows']?.inject?.dll, 'AstralValheimNet.dll');
  });

  test('process_udp forged alliance', () {
    final cfg = GameAssistLanGameDiscoverConfig.tryParse({
      'id': 'scfa',
      'type': 'process_udp',
      'parser': 'scfa_lan',
      'beacon_port': 15000,
      'process': ['game.exe', 'ForgedAlliance.exe'],
      'window': ['Forged Alliance'],
      'title': '{player} * Astral',
    });
    expect(cfg, isNotNull);
    final e = cfg!.entries.single;
    expect(e.type, 'process_udp');
    expect(e.parser, 'scfa_lan');
    expect(e.beaconPort, 15000);
    expect(e.process, ['game.exe', 'ForgedAlliance.exe']);
    expect(e.window, ['Forged Alliance']);
    expect(e.title, '{player} * Astral');
  });

  test('process_udp skips mDNS and other non-lobby ports', () {
    expect(isNonLobbyUdpPort(5353), isTrue);
    expect(isNonLobbyUdpPort(1900), isTrue);
    expect(isNonLobbyUdpPort(53), isTrue);
    expect(isNonLobbyUdpPort(62320), isFalse);
    expect(isNonLobbyUdpPort(58336), isFalse);
  });

  test('scfa lobby keeps probed port, drops join/peer ports', () {
    expect(
      selectScfaLobbyPorts(
        udpPorts: [57431, 50122, 49801],
        probedOk: {57431},
        lastLobbyPort: null,
      ),
      [57431],
    );
    expect(
      selectScfaLobbyPorts(
        udpPorts: [57431, 50122],
        probedOk: {},
        lastLobbyPort: 57431,
      ),
      [57431],
    );
    expect(
      selectScfaLobbyPorts(
        udpPorts: [59179],
        probedOk: {},
        lastLobbyPort: null,
      ),
      [59179],
    );
    expect(
      selectScfaLobbyPorts(
        udpPorts: [50122, 49801],
        probedOk: {},
        lastLobbyPort: 57431,
      ),
      isEmpty,
    );
  });

  test('missing discover is null', () {
    expect(GameAssistLanGameDiscoverConfig.tryParse(null), isNull);
    expect(GameAssistLanGameDiscoverConfig.tryParse(<String, dynamic>{}), isNull);
  });

  test('magic_wall is per exe with independent rules', () {
    expect(GameAssistMagicWallConfig.parse(null).isActive, isFalse);
    expect(GameAssistMagicWallConfig.parse(false).isActive, isFalse);

    final fromTrue = GameAssistMagicWallConfig.parse(true);
    expect(fromTrue.isActive, isFalse);
    expect(fromTrue.targets, isEmpty);

    final fromList = GameAssistMagicWallConfig.parse(['Raft.exe', 'valheim.exe']);
    expect(fromList.targets.map((e) => e.process).toList(), [
      'Raft.exe',
      'valheim.exe',
    ]);
    expect(fromList.targets.every((e) => e.rules.isEmpty), isTrue);

    final perExe = GameAssistMagicWallConfig.parse({
      'valheim.exe': [
        {
          'action': 'allow',
          'protocol': 'udp',
          'local_port': '2456',
        },
      ],
      'game.exe': [
        {
          'action': 'allow',
          'protocol': 'udp',
          'local_port': '15000',
        },
      ],
      'Raft.exe': true,
    });
    expect(perExe.isActive, isTrue);
    expect(perExe.targets, hasLength(2));
    final byName = {for (final t in perExe.targets) t.process: t};
    expect(byName['valheim.exe']!.rules.single.localPort, '2456');
    expect(byName['game.exe']!.rules.single.localPort, '15000');
    expect(byName.containsKey('Raft.exe'), isFalse);

    final listed = GameAssistMagicWallConfig.parse([
      {
        'process': 'valheim.exe',
        'rules': [
          {'protocol': 'udp', 'local_port': '2456'},
        ],
      },
      {
        'process': ['game.exe', 'ForgedAlliance.exe'],
        'rules': [
          {'protocol': 'udp', 'local_port': '15000'},
        ],
      },
    ]);
    expect(listed.targets, hasLength(3));
    expect(
      listed.targets.singleWhere((e) => e.process == 'ForgedAlliance.exe').rules.single.localPort,
      '15000',
    );

    final off = GameAssistMagicWallConfig.parse({
      'enabled': false,
      'valheim.exe': true,
    });
    expect(off.isActive, isFalse);

    final platform = GameAssistPlatformRules.fromJson({
      'magic_wall': {
        'valheim.exe': [
          {'protocol': 'udp', 'local_port': '2456'},
        ],
      },
      'inject': {
        'type': 'mono',
        'process': ['other.exe'],
        'dll': 'AstralValheimNet.dll',
        'namespace': 'AstralValheimNet',
        'class': 'Loader',
      },
    });
    expect(platform.magicWall.isActive, isTrue);
    expect(platform.magicWallProcessNames, ['valheim.exe']);
    expect(platform.inject?.process, ['other.exe']);
  });

  test('network protocol defaults to udp', () {
    expect(GameAssistNetworkProtocol.parse(null), GameAssistNetworkProtocol.udp);
    expect(GameAssistNetworkProtocol.parse(''), GameAssistNetworkProtocol.udp);
    expect(GameAssistNetworkProtocol.parse('UDP'), GameAssistNetworkProtocol.udp);
    expect(GameAssistNetworkProtocol.parse('tcp'), GameAssistNetworkProtocol.tcp);
    expect(GameAssistNetworkProtocol.parse('TCP'), GameAssistNetworkProtocol.tcp);

    final omitted = GameAssistNetworkConfig.fromJson({});
    expect(omitted.protocol, GameAssistNetworkProtocol.udp);
    expect(omitted.protocolSpecified, isFalse);

    final tcp = GameAssistNetworkConfig.fromJson({'protocol': 'tcp'});
    expect(tcp.protocol, GameAssistNetworkProtocol.tcp);
    expect(tcp.protocolSpecified, isTrue);

    final localTcp = GameAssistPlatformRules.fromJson({
      'network': {'protocol': 'tcp'},
    });
    final remotePlain = GameAssistPlatformRules.fromJson({
      'network': {'enable_udp_broadcast_relay': true},
    });
    final merged = localTcp.mergePreferRemote(remotePlain);
    expect(merged.network.protocol, GameAssistNetworkProtocol.tcp);
    expect(merged.network.enableUdpBroadcastRelay, isTrue);
  });
}
