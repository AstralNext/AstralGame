import 'package:astral_game/utils/room_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildJoinShareUrl prefers short code', () {
    expect(
      buildJoinShareUrl(shortCode: '123456789', offlineInvite: 'AG1.abc'),
      'https://next.astral.fan/j?c=123456789',
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
      joinShareUrlFromCode('123456789'),
      'https://next.astral.fan/j?c=123456789',
    );
    expect(
      joinShareUrlFromCode('AG1.offlineToken'),
      'https://next.astral.fan/j?c=AG1.offlineToken',
    );
  });

  test('extractJoinToken from next.astral.fan', () {
    expect(
      extractJoinToken('https://next.astral.fan/j?c=123456789'),
      '123456789',
    );
  });

  test('extractJoinToken from astralgame://', () {
    expect(
      extractJoinToken('astralgame://join?c=123456789'),
      '123456789',
    );
    expect(
      extractJoinToken('astralgame://j/123456789'),
      '123456789',
    );
  });

  test('extractJoinToken from legacy astral.fan', () {
    expect(
      extractJoinToken('https://astral.fan/j?c=123456789'),
      '123456789',
    );
  });

  test('extractJoinToken from message with embedded url', () {
    expect(
      extractJoinToken('一起来玩 Minecraft\nhttps://next.astral.fan/j?c=123456789'),
      '123456789',
    );
  });

  test('extractJoinToken short code and offline', () {
    expect(extractJoinToken('123456789'), '123456789');
    expect(extractJoinToken('AG1.offlineToken'), 'AG1.offlineToken');
  });

  test('extractJoinToken ignores widget deep links', () {
    expect(extractJoinToken('astralgame://widget/connect'), isNull);
    expect(extractJoinToken('astralgame://widget/rooms?code=123456789'), isNull);
  });

  test('extractJoinToken from www and fragment', () {
    expect(
      extractJoinToken('https://www.next.astral.fan/j#123456789'),
      '123456789',
    );
  });

  test('looksLikeJoinToken', () {
    expect(looksLikeJoinToken('123456789'), isTrue);
    expect(looksLikeJoinToken('AG1.offlineToken'), isTrue);
    expect(looksLikeJoinToken('hello'), isFalse);
  });
}
