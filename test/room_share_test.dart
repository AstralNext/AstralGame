import 'package:astral_game/utils/room_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildJoinShareUrl prefers short code', () {
    expect(
      buildJoinShareUrl(shortCode: 'JHJM8Z', offlineInvite: 'AG1.abc'),
      'https://next.astral.fan/j?c=JHJM8Z',
    );
  });

  test('buildJoinShareUrl falls back to offline invite', () {
    expect(
      buildJoinShareUrl(shortCode: '', offlineInvite: 'AG1.offlineToken'),
      'https://next.astral.fan/j?c=AG1.offlineToken',
    );
  });

  test('joinShareUrlFromCode accepts short or offline', () {
    expect(
      joinShareUrlFromCode('JHJM8Z'),
      'https://next.astral.fan/j?c=JHJM8Z',
    );
    expect(
      joinShareUrlFromCode('jhjm8z'),
      'https://next.astral.fan/j?c=JHJM8Z',
    );
    expect(
      joinShareUrlFromCode('AG1.offlineToken'),
      'https://next.astral.fan/j?c=AG1.offlineToken',
    );
  });

  test('extractJoinToken from next.astral.fan', () {
    expect(extractJoinToken('https://next.astral.fan/j?c=JHJM8Z'), 'JHJM8Z');
  });

  test('extractJoinToken from astralgame://', () {
    expect(extractJoinToken('astralgame://join?c=JHJM8Z'), 'JHJM8Z');
    expect(extractJoinToken('astralgame://j/JHJM8Z'), 'JHJM8Z');
  });

  test('extractJoinToken rejects legacy astral.fan (no next prefix)', () {
    expect(extractJoinToken('https://astral.fan/j?c=JHJM8Z'), isNull);
    expect(extractJoinToken('https://www.astral.fan/j?c=JHJM8Z'), isNull);
  });

  test('extractJoinToken from message with embedded url', () {
    expect(
      extractJoinToken('一起来玩 Minecraft\nhttps://next.astral.fan/j?c=JHJM8Z'),
      'JHJM8Z',
    );
  });

  test('extractJoinToken short code and offline', () {
    expect(extractJoinToken('JHJM8Z'), 'JHJM8Z');
    expect(extractJoinToken('jhjm8z'), 'jhjm8z');
    // 9 位短码为旧版兼容格式，已移除，不再识别
    expect(extractJoinToken('123456789'), isNull);
    expect(extractJoinToken('AG1.offlineToken'), 'AG1.offlineToken');
  });

  test('extractJoinToken ignores widget deep links', () {
    expect(extractJoinToken('astralgame://widget/connect'), isNull);
    expect(
      extractJoinToken('astralgame://widget/rooms?code=123456789'),
      isNull,
    );
  });

  test('extractJoinToken from www and fragment', () {
    expect(extractJoinToken('https://www.next.astral.fan/j#JHJM8Z'), 'JHJM8Z');
  });

  test('looksLikeJoinToken', () {
    expect(looksLikeJoinToken('JHJM8Z'), isTrue);
    expect(looksLikeJoinToken('jhjm8z'), isTrue);
    // 9 位短码为旧版兼容格式，已移除，不再识别
    expect(looksLikeJoinToken('123456789'), isFalse);
    expect(looksLikeJoinToken('AG1.offlineToken'), isTrue);
    expect(looksLikeJoinToken('hello'), isFalse);
  });

  test('normalizeShareCode crockford aliases', () {
    expect(normalizeShareCode('jh j-m8z'), 'JHJM8Z');
    expect(normalizeShareCode('oil'), '011');
  });

  test('requireJoinInviteToken rejects empty and unknown text', () {
    expect(() => requireJoinInviteToken(''), throwsA(isA<StateError>()));
    expect(
      () => requireJoinInviteToken('not-a-invite'),
      throwsA(isA<StateError>()),
    );
  });

  test('requireJoinInviteToken accepts short code and join url', () {
    expect(requireJoinInviteToken('JHJM8Z'), 'JHJM8Z');
    expect(
      requireJoinInviteToken('https://next.astral.fan/j?c=JHJM8Z'),
      'JHJM8Z',
    );
  });
}
