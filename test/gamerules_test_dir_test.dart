import 'dart:io';

import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('listTestRuleFiles prefers gamerules.json then rules.json', () {
    final dir = Directory.systemTemp.createTempSync('astral-gamerules-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    File(p.join(dir.path, 'zzz.json')).writeAsStringSync('{}');
    File(p.join(dir.path, 'rules.json')).writeAsStringSync('{}');
    File(p.join(dir.path, 'gamerules.json')).writeAsStringSync('{}');
    File(p.join(dir.path, 'notes.txt')).writeAsStringSync('no');

    final files = GameAssistRulesService.listTestRuleFiles([dir]);
    expect(files.map((f) => p.basename(f.path)), [
      'gamerules.json',
      'rules.json',
      'zzz.json',
    ]);
  });

  test('listTestRuleFiles skips missing dirs', () {
    expect(
      GameAssistRulesService.listTestRuleFiles([
        Directory(p.join(Directory.systemTemp.path, 'no-such-astral-gamerules')),
      ]),
      isEmpty,
    );
  });
}
