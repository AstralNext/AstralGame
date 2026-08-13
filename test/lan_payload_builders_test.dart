import 'dart:convert';

import 'package:astral_game/data/services/lan_payload_builders.dart';
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

  test('minecraft_motd rebuild', () {
    final bytes = buildMinecraftMotdPayload(title: '二哈 · Minecraft', port: 25565);
    expect(bytes, isNotNull);
    expect(
      utf8.decode(bytes!),
      '[MOTD]二哈 · Minecraft[/MOTD][AD]25565[/AD]',
    );
  });
}
