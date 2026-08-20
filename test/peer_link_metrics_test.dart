import 'package:astral_game/data/models/peer_link_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hysteresis ignores sub-8ms jitter', () {
    const a = PeerLinkMetrics(latencyMs: 40, lossRate: 0);
    const b = PeerLinkMetrics(latencyMs: 47, lossRate: 0);
    expect(a.visiblyDiffersFrom(b), isFalse);
  });

  test('hysteresis fires at 8ms', () {
    const a = PeerLinkMetrics(latencyMs: 40, lossRate: 0);
    const b = PeerLinkMetrics(latencyMs: 48, lossRate: 0);
    expect(a.visiblyDiffersFrom(b), isTrue);
  });

  test('loss rate compared at 0.1%', () {
    const a = PeerLinkMetrics(latencyMs: 40, lossRate: 1.02);
    const b = PeerLinkMetrics(latencyMs: 40, lossRate: 1.04);
    const c = PeerLinkMetrics(latencyMs: 40, lossRate: 1.15);
    expect(a.visiblyDiffersFrom(b), isFalse);
    expect(a.visiblyDiffersFrom(c), isTrue);
  });
}
