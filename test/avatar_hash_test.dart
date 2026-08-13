import 'dart:typed_data';

import 'package:astral_game/utils/avatar_hash.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty avatar has no hash', () {
    expect(avatarContentHash(null), isNull);
    expect(avatarContentHash(Uint8List(0)), isNull);
  });

  test('same bytes same hash', () {
    final a = Uint8List.fromList([1, 2, 3, 4]);
    final b = Uint8List.fromList([1, 2, 3, 4]);
    expect(avatarContentHash(a), avatarContentHash(b));
  });

  test('only send bytes when hash differs', () {
    final hash = avatarContentHash(Uint8List.fromList([9, 8, 7]));
    expect(shouldSendAvatarBytes(null, hash), isTrue);
    expect(shouldSendAvatarBytes('', hash), isTrue);
    expect(shouldSendAvatarBytes(hash, hash), isFalse);
    expect(shouldSendAvatarBytes('other', hash), isTrue);
    expect(shouldSendAvatarBytes(null, null), isFalse);
  });

  test('avatarHashFromParams', () {
    expect(avatarHashFromParams(null), isNull);
    expect(avatarHashFromParams({'avatarHash': '  abc  '}), 'abc');
    expect(avatarHashFromParams({'avatarHash': ''}), isNull);
  });
}
