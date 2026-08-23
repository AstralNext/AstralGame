import 'dart:typed_data';

import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/data/models/local_self_nodes.dart';
import 'package:astral_rust_core/p2p_service.dart';
import 'package:flutter_test/flutter_test.dart';

KVNodeInfo _kv({
  required int peerId,
  String hostname = 'me',
  String ipv4 = '',
  String version = '2.6.4',
  int cost = 0,
}) {
  return KVNodeInfo(
    peerId: peerId,
    hostname: hostname,
    ipv4: ipv4,
    ipv6: '',
    latencyMs: 0,
    nat: 'Unknown',
    hops: const [],
    lossRate: 0,
    connections: const [],
    tunnelProto: '-',
    connType: 'Local',
    rxBytes: BigInt.zero,
    txBytes: BigInt.zero,
    version: version,
    cost: cost,
    remoteStaticPubkeyB64: '',
    isCredentialPeer: false,
  );
}

EnhancedNodeInfo _node({
  required int peerId,
  String ipv4 = '',
  String? customName,
}) {
  return EnhancedNodeInfo(
    baseInfo: _kv(peerId: peerId, ipv4: ipv4),
    customName: customName,
    avatar: Uint8List.fromList(const [1]),
  );
}

void main() {
  test('collapse merges synthetic and real local into one row with best IP', () {
    final collapsed = collapseLocalSelfNodes(
      [
        _node(peerId: 0, ipv4: '10.126.126.1'),
        _node(peerId: 42, ipv4: ''),
        _node(peerId: 7, ipv4: '10.126.126.9', customName: 'friend'),
      ],
      isLocalPeer: (id) => id == 0 || id == 42,
    );

    expect(collapsed, hasLength(2));
    expect(collapsed.map((n) => n.peerId).toList(), [0, 7]);
    final self = collapsed.firstWhere((n) => n.peerId == 0);
    expect(self.hasValidIpv4, isTrue);
    expect(self.ipv4, '10.126.126.1');
    expect(collapsed.any((n) => n.peerId == 42), isFalse);
  });

  test('collapse prefers IP from real local when synthetic is empty', () {
    final collapsed = collapseLocalSelfNodes(
      [
        _node(peerId: 0, ipv4: ''),
        _node(peerId: 99, ipv4: '10.126.126.1/24'),
      ],
      isLocalPeer: (id) => id == 0 || id == 99,
    );

    expect(collapsed, hasLength(1));
    expect(collapsed.single.peerId, 0);
    expect(stripHost(collapsed.single.ipv4), '10.126.126.1');
  });

  test('virtualIpv4FromNodes reads collapsed self', () {
    final nodes = collapseLocalSelfNodes(
      [
        _node(peerId: 0, ipv4: ''),
        _node(peerId: 3, ipv4: '10.1.2.3'),
      ],
      isLocalPeer: (id) => id == 0 || id == 3,
    );
    expect(
      virtualIpv4FromNodes(nodes, isLocalPeer: (id) => id == 0),
      '10.1.2.3',
    );
  });
}

String stripHost(String raw) {
  final slash = raw.indexOf('/');
  return slash >= 0 ? raw.substring(0, slash) : raw;
}
