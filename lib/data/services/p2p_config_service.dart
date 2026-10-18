import 'dart:math';

import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';

class P2PConfigService {
  P2PConfigService(this._appSettings, this._serverState);
  final AppSettingsService _appSettings;
  final ServerState _serverState;

  String generateRoomCode({int length = 10}) {
    const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// 构建 TOML：双方共享 [roomPassword] 作为 network_secret（旧版密码进房）。
  ///
  /// [isDhcp] 控制是否让 EasyTier 自动分配虚拟 IP；打开时用 [kRoomDhcpIpv4Cidr]
  /// 作为初始网段，关闭时使用 [virtualIp] 作为固定 IP（写入顶层 `ipv4`）。
  /// [isDhcpv6] 控制是否自动分配虚拟 IPv6；打开时用 [kRoomDhcpIpv6Cidr]，
  /// 关闭时使用 [virtualIpv6] 作为固定 IPv6（写入顶层 `ipv6`）。
  String buildTomlConfig(
    String roomName,
    String roomPassword, {
    List<PeerEndpoint>? peersOverride,
    bool enableUdpBroadcastRelay = false,
    GameAssistNetworkProtocol protocol = GameAssistNetworkProtocol.udp,
    bool isDhcp = true,
    bool isDhcpv6 = true,
    String? virtualIp,
    String? virtualIpv6,
  }) {
    final disableP2p = _appSettings.isDisableP2p();
    final rawUsername = _appSettings.getUsername().trim();
    final hostname = rawUsername.isEmpty ? 'Astral' : rawUsername;

    // peersOverride != null：加入短码/离线邀请，只用载荷里的服务器，绝不回退本地列表。
    // peersOverride == null：建房，用本机当前启用的服务器。
    final peers = <PeerEndpoint>[];
    if (peersOverride != null) {
      peers.addAll(peersOverride.where((p) => p.uri.trim().isNotEmpty));
    } else {
      peers.addAll(enabledPeers());
    }

    final peerBlock = peers.map(_peerTomlBlock).join('\n\n');

    // 游戏 JSON 规则驱动；未命中规则时不转发。
    final udpRelay = enableUdpBroadcastRelay;
    final udpBroadcastFlag =
        RuntimePlatform.operatingSystem == 'windows' && udpRelay
        ? 'enable_udp_broadcast_relay = true\n'
        : '';

    // 关闭 DHCP 时，把用户填写的固定 IP 写入 EasyTier 顶层 ipv4 键（与 dhcp 平级）。
    // 不能写进 [flags]：flags 只认预定义键，未知键会被 EasyTier 静默丢弃，
    // 导致 DHCP 已关、固定 IP 又没生效，虚拟网卡无 IP（UI 表现为"未分配 IP"）。
    final trimmedIp = virtualIp?.trim() ?? '';
    final fixedIpv4Line = (!isDhcp && trimmedIp.isNotEmpty)
        ? 'ipv4 = "${_escapeString(trimmedIp)}"\n'
        : '';

    // 关闭 DHCPv6 时，把用户填写的固定 IPv6 写入 EasyTier 顶层 ipv6 键（与 dhcpv6 平级）。
    final trimmedIpv6 = virtualIpv6?.trim() ?? '';
    final fixedIpv6Line = (!isDhcpv6 && trimmedIpv6.isNotEmpty)
        ? 'ipv6 = "${_escapeString(trimmedIpv6)}"\n'
        : '';

    // 打开 DHCP 时直接写"初始网段"而不是裸 true：EasyTier 的 `dhcp` / `dhcpv6`
    // 字段接受 bool 或 CIDR 字符串（untagged DhcpConfig）。显式给网段可避开默认
    // 的 10.126.126.0/24 与 fd6b:8c2d:91e4::/64，减少与家用网段撞车。
    final dhcpLine = isDhcp ? 'dhcp = "$kRoomDhcpIpv4Cidr"' : 'dhcp = false';
    final dhcpv6Line = isDhcpv6
        ? 'dhcpv6 = "$kRoomDhcpIpv6Cidr"'
        : 'dhcpv6 = false';

    final identityBlock =
        '''
[network_identity]
network_name = "${_escapeString(roomName)}"
network_secret = "${_escapeString(roomPassword)}"
''';

    appLogger.i(
      '[P2PConfigService] buildTomlConfig room=$roomName '
      'shared_secret=true dhcp=$isDhcp dhcpv6=$isDhcpv6 disable_p2p=$disableP2p '
      'protocol=${protocol.name} udp_broadcast_relay=$udpRelay '
      'virtual_ip=${(!isDhcp && trimmedIp.isNotEmpty) ? trimmedIp : "auto"} '
      'virtual_ipv6=${(!isDhcpv6 && trimmedIpv6.isNotEmpty) ? trimmedIpv6 : "auto"} '
      'ipv4_cidr=${isDhcp ? kRoomDhcpIpv4Cidr : "-"} '
      'ipv6_cidr=${isDhcpv6 ? kRoomDhcpIpv6Cidr : "-"} '
      'peers=${peers.length}',
    );

    return '''
instance_name = "AstralGame"
hostname = "${_escapeString(hostname)}"
$dhcpLine
$dhcpv6Line
$fixedIpv4Line$fixedIpv6Line
listeners = [
    "tcp://0.0.0.0:0",
    "udp://0.0.0.0:0",
]

$identityBlock
${peerBlock.isNotEmpty ? '$peerBlock\n\n' : ''}${_flagsBlock(disableP2p: disableP2p, udpBroadcastFlag: udpBroadcastFlag, protocol: protocol)}
''';
  }

  /// UDP / TCP 两套 EasyTier `[flags]`（与 Astral-Client-UDP/TCP.toml 对齐）。
  static String _flagsBlock({
    required bool disableP2p,
    required String udpBroadcastFlag,
    required GameAssistNetworkProtocol protocol,
  }) {
    final quic = protocol == GameAssistNetworkProtocol.tcp
        ? '''
disable_quic_input = false
disable_relay_quic = false
enable_quic_proxy = true
enable_relay_foreign_network_quic = true
'''
        : '''
disable_quic_input = true
disable_relay_quic = true
enable_relay_foreign_network_quic = false
''';
    return '''
[flags]
disable_p2p = $disableP2p
$udpBroadcastFlag
data_compress_algo = 2
default_protocol = "tcp"
dev_name = "ASGame"
disable_kcp_input = true
disable_relay_kcp = true
enable_relay_foreign_network_kcp = false
$quic''';
  }

  String _peerTomlBlock(PeerEndpoint peer) {
    final uri = peer.uri.trim();
    return '[[peer]]\nuri = "${_escapeString(uri)}"';
  }

  /// 当前启用的 peer（仅 URI）；供建房短码与 TOML。
  List<PeerEndpoint> enabledPeers() {
    final out = <PeerEndpoint>[];
    for (final server in _serverState.getEnabledServers()) {
      final url = server.url;
      final trimmed = url.trim();
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)) {
        appLogger.w('[P2PConfigService] 跳过无效服务器地址: $trimmed');
        continue;
      }
      out.add(PeerEndpoint(uri: trimmed));
    }
    return out;
  }

  String _escapeString(String s) =>
      s.replaceAll('\\', r'\\').replaceAll('"', r'\"');
}
