import 'dart:typed_data';

import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_rust_core/p2p_service.dart';
import 'package:flutter_test/flutter_test.dart';

KVNodeInfo _kv({
  int peerId = 1,
  String hostname = 'alice',
  String ipv4 = '10.144.0.2',
  String ipv6 = '',
  double latencyMs = 40,
  double lossRate = 0,
  String version = '1.0.0',
  int cost = 1,
}) {
  return KVNodeInfo(
    peerId: peerId,
    hostname: hostname,
    ipv4: ipv4,
    ipv6: ipv6,
    latencyMs: latencyMs,
    nat: 'Unknown',
    hops: const [],
    lossRate: lossRate,
    connections: const [],
    tunnelProto: 'udp',
    connType: 'p2p',
    rxBytes: BigInt.zero,
    txBytes: BigInt.zero,
    version: version,
    cost: cost,
    remoteStaticPubkeyB64: '',
    isCredentialPeer: false,
  );
}

void main() {
  test('UI snapshot ignores latency and traffic jitter', () {
    final a = EnhancedNodeInfo(baseInfo: _kv(lossRate: 0.1));
    final b = EnhancedNodeInfo(
      baseInfo: _kv(latencyMs: 48, lossRate: 1.5).copyWithTx(),
    );
    expect(sameKvNodeUiSnapshot(a.baseInfo, b.baseInfo), isTrue);
    expect(sameEnhancedPollSnapshot(a, b), isTrue);
  });

  test('UI snapshot changes when identity fields change', () {
    final a = EnhancedNodeInfo(baseInfo: _kv());
    expect(
      sameEnhancedPollSnapshot(
        a,
        EnhancedNodeInfo(baseInfo: _kv(ipv4: '10.144.0.9')),
      ),
      isFalse,
    );
    expect(
      sameEnhancedPollSnapshot(
        a,
        EnhancedNodeInfo(baseInfo: _kv(), customName: 'Bob'),
      ),
      isFalse,
    );
    expect(
      sameEnhancedPollSnapshot(
        a,
        EnhancedNodeInfo(
          baseInfo: _kv(),
          avatar: Uint8List.fromList(const [1, 2, 3]),
        ),
      ),
      isFalse,
    );
  });

  test('user list snapshot requires same peer order and length', () {
    final a = EnhancedNodeInfo(baseInfo: _kv());
    final b = EnhancedNodeInfo(baseInfo: _kv(peerId: 2, hostname: 'bob'));
    expect(sameUserNodesUiSnapshot([a, b], [a, b]), isTrue);
    expect(sameUserNodesUiSnapshot([a, b], [b, a]), isFalse);
    expect(sameUserNodesUiSnapshot([a], [a, b]), isFalse);
  });
}

extension on KVNodeInfo {
  KVNodeInfo copyWithTx() {
    return KVNodeInfo(
      peerId: peerId,
      hostname: hostname,
      ipv4: ipv4,
      ipv6: ipv6,
      latencyMs: latencyMs,
      nat: nat,
      hops: hops,
      lossRate: lossRate,
      connections: connections,
      tunnelProto: tunnelProto,
      connType: connType,
      rxBytes: BigInt.from(99),
      txBytes: BigInt.from(88),
      version: version,
      cost: cost,
      remoteStaticPubkeyB64: remoteStaticPubkeyB64,
      isCredentialPeer: isCredentialPeer,
    );
  }
}
