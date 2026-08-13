import 'package:astral_game/utils/net_addr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stripIpv4Host drops cidr and unspecified', () {
    expect(stripIpv4Host('10.0.0.2/24'), '10.0.0.2');
    expect(stripIpv4Host('0.0.0.0'), isNull);
    expect(stripIpv4Host(''), isNull);
  });

  test('stripCidrHost ipv6', () {
    expect(stripCidrHost('fd00::1/64', unspecified: const {'::'}), 'fd00::1');
    expect(stripCidrHost('::', unspecified: const {'::'}), isNull);
  });
}
