import 'package:astral_game/data/services/network_optimize_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseInstalled reads status line', () {
    expect(parseInstalled('installed=yes\nstate=Running\n'), isTrue);
    expect(parseInstalled('installed=no\nstate=not_installed\n'), isFalse);
    expect(parseInstalled(''), isFalse);
  });
}
