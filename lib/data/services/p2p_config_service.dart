import 'dart:math';

import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';

class P2PConfigService {
  final AppSettingsService _appSettings;
  final ServerState _serverState;

  P2PConfigService(this._appSettings, this._serverState);

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
  String buildTomlConfig(
    String roomName,
    String roomPassword, {
    List<PeerEndpoint>? peersOverride,
    bool? enableUdpBroadcastRelay,
    GameAssistNetworkProtocol protocol = GameAssistNetworkProtocol.udp,
  }) {
    final disableP2p = _appSettings.isDisableP2p();
    final rawUsername = _appSettings.getUsername().trim();
    final hostname = rawUsername.isEmpty ? 'Astral' : rawUsername;

    // peersOverride != null：加入短码/离线邀请，只用载荷里的服务器，绝不回退本地列表。
    // peersOverride == null：建房，用本机当前启用的服务器。
    final peers = <PeerEndpoint>[];
    if (peersOverride != null) {
      peers.addAll(
        peersOverride.where((p) => p.uri.trim().isNotEmpty),
      );
    } else {
      peers.addAll(enabledPeers());
    }

    final peerBlock = peers.map(_peerTomlBlock).join('\n\n');

    // 游戏 JSON 规则优先；否则回退用户设置强制开关。
    final udpRelay =
        enableUdpBroadcastRelay ?? _appSettings.isEnableUdpBroadcastRelay();
    final udpBroadcastFlag =
        RuntimePlatform.operatingSystem == 'windows' && udpRelay
            ? 'enable_udp_broadcast_relay = true\n'
            : '';

    final identityBlock = '''
[network_identity]
network_name = "${_escapeString(roomName)}"
network_secret = "${_escapeString(roomPassword)}"
''';

    appLogger.i(
      '[P2PConfigService] buildTomlConfig room=$roomName '
      'shared_secret=true dhcp=true disable_p2p=$disableP2p '
      'protocol=${protocol.name} udp_broadcast_relay=$udpRelay '
      'peers=${peers.length}',
    );

    return '''
instance_name = "AstralGame"
hostname = "${_escapeString(hostname)}"
dhcp = true
listeners = [
    "tcp://0.0.0.0:0",
    "udp://0.0.0.0:0",
]

$identityBlock
${peerBlock.isNotEmpty ? '$peerBlock\n\n' : ''}${_flagsBlock(
      disableP2p: disableP2p,
      udpBroadcastFlag: udpBroadcastFlag,
      protocol: protocol,
    )}
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
${udpBroadcastFlag}data_compress_algo = 2
default_protocol = "tcp"
dev_name = "Astral"
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
