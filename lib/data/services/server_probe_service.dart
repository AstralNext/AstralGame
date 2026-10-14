import 'package:astral_game/data/models/server_mod.dart';

/// 一次「模拟加入节点」探测的结果。
///
/// 字段含义对齐 EasyTier 握手/路由信息：
/// - [isEasyTier] 等价于握手包里 `magic == 0xd1e1a5e1` 是否校验通过；
/// - [version] 等价于 OSPF 路由里 `RoutePeerInfo.easytier_version`（软件版本）；
/// - [protocolVersion] 等价于握手包里的 `HandshakeRequest.version`（协议版本）。
class ServerProbeResult {
  const ServerProbeResult({
    required this.isEasyTier,
    this.version,
    this.protocolVersion,
  });

  /// 对端是否为 EasyTier 服务器。
  final bool isEasyTier;

  /// EasyTier 软件版本；非 ET 服务器为 null。
  final String? version;

  /// EasyTier 协议版本；非 ET 服务器为 null。
  final int? protocolVersion;
}

/// 服务器「加入节点」探测（模拟实现）。
///
/// 真机流程应是：向对端发起一次 EasyTier TCP 握手（`tcp://` 帧内 4 字节小端
/// 长度 + 16 字节 [PeerManagerHeader]，`packet_type = HandShake(2)`），校验
/// 回包里的魔数是否为 `0xd1e1a5e1`，据此判断是否 ET 服务器；版本则需进入同一
/// 网络后从路由信息中读取。此处不真正建连，仅按服务器地址确定性生成结果，
/// 保证同一服务器每次探测结果一致、可复现。
class ServerProbeService {
  /// ET 握手魔数（easytier-core `peer_conn.rs`：`const MAGIC = 0xd1e1a5e1`）。
  static const int easytierHandshakeMagic = 0xd1e1a5e1;

  /// ET 握手协议版本常量（`peer_conn.rs`：`const VERSION = 1`）。
  static const int easytierProtocolVersion = 1;

  /// 仓库内 ET 基线版本（`rust/Cargo.lock`：easytier 2.7.0）。
  static const String easytierBaseVersion = '2.7.0';

  /// EasyTier 支持的接入协议（其余 scheme 视为非 ET 端点）。
  static const Set<String> _easyTierSchemes = {
    'tcp',
    'udp',
    'ws',
    'wss',
    'quic',
    'wg',
  };

  /// 模拟一次「加入节点」探测，只判断是否 ET 服务器并读取版本（不含延迟）。
  ///
  /// 延迟由 TCP ping 单独测得，这里不产出 RTT。
  Future<ServerProbeResult> probe(ServerMod server) async {
    final seed = _fnv1a(server.url);
    // 模拟握手 + 拉取首个路由信息的耗时，确定性 320~1120ms。
    await Future<void>.delayed(Duration(milliseconds: 320 + seed % 800));

    if (!_looksLikeEasyTier(server.url, seed)) {
      // 可达但不是 ET 端点：握手魔数不匹配。
      return const ServerProbeResult(isEasyTier: false);
    }
    return ServerProbeResult(
      isEasyTier: true,
      version: '$easytierBaseVersion-${_shortCommit(seed)}',
      protocolVersion: easytierProtocolVersion,
    );
  }

  /// 是否为 ET 端点：scheme 需在 ET 支持范围内，另按哈希少量命中非 ET。
  bool _looksLikeEasyTier(String url, int seed) {
    final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
    if (scheme == null || !_easyTierSchemes.contains(scheme)) return false;
    return seed % 8 != 0;
  }

  /// FNV-1a 32 位哈希，保证跨进程稳定（`String.hashCode` 不保证稳定）。
  static int _fnv1a(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  /// 由哈希生成 8 位十六进制短提交号，形如真实 ET 版本的 `2.7.0-1a2b3c4d`。
  static String _shortCommit(int seed) =>
      seed.toRadixString(16).padLeft(8, '0');
}
