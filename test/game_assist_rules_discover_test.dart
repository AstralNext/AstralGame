import 'package:astral_game/data/models/game_assist_rules.dart';
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

  test('missing discover is null', () {
    expect(GameAssistLanGameDiscoverConfig.tryParse(null), isNull);
    expect(GameAssistLanGameDiscoverConfig.tryParse(<String, dynamic>{}), isNull);
  });
}
