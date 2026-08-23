import 'package:astral_game/data/models/enhanced_node_info.dart';
import 'package:astral_game/utils/net_addr.dart';
import 'package:astral_rust_core/p2p_service.dart' show KVNodeInfo;

/// EasyTier / astral_rust_core 会同时给出：
/// - `peer_id=0` 合成本机哨兵（带 `my_node_info.virtual_ipv4`）
/// - routes 表里真实本机 `peer_id`（DHCP 前后 ipv4 可能仍空）
///
/// 成员列表必须只保留 **一条** 本机行，否则会出现右侧已解析虚拟 IP、
/// 左侧却渲染到「空地址的那条本机」上的不一致。
List<EnhancedNodeInfo> collapseLocalSelfNodes(
  List<EnhancedNodeInfo> nodes, {
  required bool Function(int peerId) isLocalPeer,
  int canonicalPeerId = 0,
}) {
  final remotes = <EnhancedNodeInfo>[];
  final locals = <EnhancedNodeInfo>[];
  for (final n in nodes) {
    if (isLocalPeer(n.peerId)) {
      locals.add(n);
    } else {
      remotes.add(n);
    }
  }
  if (locals.isEmpty) {
    return List<EnhancedNodeInfo>.of(nodes);
  }
  if (locals.length == 1 && locals.first.peerId == canonicalPeerId) {
    return List<EnhancedNodeInfo>.of(nodes);
  }

  final merged = mergeLocalSelfEntries(
    locals,
    canonicalPeerId: canonicalPeerId,
  );
  final out = <EnhancedNodeInfo>[merged, ...remotes]
    ..sort((a, b) => a.peerId.compareTo(b.peerId));
  return out;
}

/// 把多条本机条目合成一条；IPv4/IPv6 取第一条合法值，其余字段择优。
EnhancedNodeInfo mergeLocalSelfEntries(
  List<EnhancedNodeInfo> locals, {
  required int canonicalPeerId,
}) {
  assert(locals.isNotEmpty);
  EnhancedNodeInfo best = locals.first;
  for (final n in locals.skip(1)) {
    best = _preferLocal(best, n);
  }

  final ipv4 = _firstValidIpv4(locals) ?? best.ipv4;
  final ipv6 = _firstValidIpv6(locals) ?? best.ipv6;
  final base = best.baseInfo;
  final mergedBase = KVNodeInfo(
    peerId: canonicalPeerId,
    hostname: base.hostname,
    ipv4: ipv4,
    ipv6: ipv6,
    latencyMs: base.latencyMs,
    nat: base.nat,
    hops: base.hops,
    lossRate: base.lossRate,
    connections: base.connections,
    tunnelProto: base.tunnelProto,
    connType: base.connType,
    rxBytes: base.rxBytes,
    txBytes: base.txBytes,
    version: base.version,
    cost: base.cost,
    remoteStaticPubkeyB64: base.remoteStaticPubkeyB64,
    isCredentialPeer: base.isCredentialPeer,
  );

  return best.copyWith(baseInfo: mergedBase);
}

String? virtualIpv4FromNodes(
  List<EnhancedNodeInfo> nodes, {
  required bool Function(int peerId) isLocalPeer,
}) {
  for (final n in nodes) {
    if (!isLocalPeer(n.peerId)) continue;
    final ip = stripIpv4Host(n.ipv4);
    if (ip != null) return ip;
  }
  return null;
}

EnhancedNodeInfo _preferLocal(EnhancedNodeInfo a, EnhancedNodeInfo b) {
  // 优先保留已有合法 IPv4 的条目作为「资料底座」。
  if (!a.hasValidIpv4 && b.hasValidIpv4) return b;
  if (a.hasValidIpv4 && !b.hasValidIpv4) return a;
  // 同有/同无 IP 时，优先哨兵 peer_id=0（与 Rust 合成本机一致）。
  if (a.peerId == 0) return a;
  if (b.peerId == 0) return b;
  return a;
}

String? _firstValidIpv4(List<EnhancedNodeInfo> locals) {
  for (final n in locals) {
    if (n.hasValidIpv4) return n.ipv4;
  }
  return null;
}

String? _firstValidIpv6(List<EnhancedNodeInfo> locals) {
  for (final n in locals) {
    if (n.hasValidIpv6) return n.ipv6;
  }
  return null;
}
