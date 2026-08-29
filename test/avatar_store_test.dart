import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/utils/avatar_hash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('astral-avatar-');
  });

  tearDown(() async {
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });

  test('setAvatar writes file + content hash', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettingsService(prefs, supportDir: dir);
    await settings.warmUpAvatar();
    final bytes = Uint8List.fromList([9, 8, 7, 6]);
    await settings.setAvatar(bytes);

    expect(settings.getAvatar(), bytes);
    expect(prefs.getString('avatar_hash'), avatarContentHash(bytes));
    expect(await File(p.join(dir.path, 'avatar.bin')).readAsBytes(), bytes);
  });

  test('clearAvatar deletes file and hash', () async {
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettingsService(prefs, supportDir: dir);
    await settings.setAvatar(Uint8List.fromList([4, 5]));
    await settings.clearAvatar();

    expect(settings.getAvatar(), isNull);
    expect(settings.getAvatarHash(), isNull);
    expect(File(p.join(dir.path, 'avatar.bin')).existsSync(), isFalse);
    expect(prefs.getString('avatar_hash'), isNull);
  });
}
