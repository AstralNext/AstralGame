import 'package:astral_game/utils/icmp_echo.dart';
import 'package:astral_game/utils/ping_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDownAll(PingUtil.close);

  test('pingHostOf from EasyTier URI', () {
    expect(pingHostOf('tcp://192.168.1.10:11010'), '192.168.1.10');
    expect(pingHostOf('udp://example.com:11010'), 'example.com');
    expect(pingHostOf('wss://relay.example.com/path'), 'relay.example.com');
    expect(pingHostOf('tcp://[2001:db8::1]:11010'), '2001:db8::1');
  });

  test('pingHostOf from host:port', () {
    expect(pingHostOf('10.0.0.1:443'), '10.0.0.1');
    expect(pingHostOf('example.com'), 'example.com');
    expect(pingHostOf('[::1]:11010'), '::1');
  });

  test('pingHostOf rejects empty and unspecified', () {
    expect(pingHostOf(''), isNull);
    expect(pingHostOf('tcp://0.0.0.0:1'), isNull);
    expect(pingHostOf(' -evil.com'), isNull);
  });

  test('icmpChecksum rfc1071', () {
    final pkt = buildIcmpEchoRequest(
      id: 0x1234,
      seq: 1,
      payload: const [1, 2, 3, 4],
    );
    expect(pkt[0], 8);
    expect(icmpChecksum(pkt), 0);
  });

  test('icmp echo localhost', () async {
    final ms = await PingUtil.pingHost('127.0.0.1');
    expect(ms, isNotNull);
  });

  test('pingMany empty and loopback batch', () async {
    expect(await PingUtil.pingMany(const []), isEmpty);
    final rtts = await PingUtil.pingMany(const [
      '127.0.0.1',
      'tcp://127.0.0.1:11010',
    ]);
    expect(rtts, hasLength(2));
    expect(rtts[0], isNotNull);
    expect(rtts[1], isNotNull);
  });
}
