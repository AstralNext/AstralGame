import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/data/state/vpn_state.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:pointycastle/export.dart';

class RoomShareCodeParts {
  final String token;
  final String roomName;

  const RoomShareCodeParts({
    required this.token,
    required this.roomName,
  });
}

class P2PConfigService {
  final AppSettingsService _appSettings;
  final ServerState _serverState;
  final VpnState _vpnState;

  P2PConfigService(this._appSettings, this._serverState, this._vpnState);

  String generateRoomCode({int length = 10}) {
    const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  String enabledServersFingerprint({int length = 8}) {
    final normalized = enabledPeers()
        .map((p) => _normalizeFullUri(p.uri) ?? p.uri.trim())
        .toList()
      ..sort();
    final digestBytes = _md5(utf8.encode(normalized.join('\n')));
    final hex = _toHex(digestBytes);
    if (length <= 0) return '';
    return hex.substring(0, length.clamp(1, hex.length));
  }

  String buildRoomShareCode({
    required String roomName,
    required String token,
  }) {
    return '${token.trim()}_${roomName.trim()}';
  }

  String normalizeRoomShareCode(String shareCode) {
    final parts = parseRoomShareCode(shareCode);
    if (parts == null) return shareCode.trim();
    return buildRoomShareCode(roomName: parts.roomName, token: parts.token);
  }

  static final _shareTokenPattern = RegExp(
    r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz]{6,20}$',
  );

  RoomShareCodeParts? parseRoomShareCode(String shareCode) {
    final trimmed = shareCode.trim();
    if (trimmed.isEmpty) return null;
    final underscore = trimmed.indexOf('_');
    if (underscore <= 0 || underscore >= trimmed.length - 1) return null;
    final token = trimmed.substring(0, underscore);
    final roomName = trimmed.substring(underscore + 1).trim();
    if (roomName.isEmpty || !_shareTokenPattern.hasMatch(token)) return null;
    return RoomShareCodeParts(token: token, roomName: roomName);
  }

  /// 构建 TOML：双方共享 [roomPassword] 作为 network_secret（旧版密码进房）。
  String buildTomlConfig(
    String roomName,
    String roomPassword, {
    List<PeerEndpoint>? peersOverride,
    bool? enableUdpBroadcastRelay,
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

    final proxyBlock = _vpnState.customRoutes.value
        .map((route) => route.trim())
        .where(_isValidCidrLike)
        .map((route) => '[[proxy_network]]\ncidr = "${_escapeString(route)}"')
        .join('\n\n');

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
      'udp_broadcast_relay=$udpRelay peers=${peers.length}',
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
${peerBlock.isNotEmpty ? '$peerBlock\n\n' : ''}${proxyBlock.isNotEmpty ? '$proxyBlock\n\n' : ''}[flags]
disable_p2p = $disableP2p
$udpBroadcastFlag
''';
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

  /// 兼容旧调用：仅 URI 列表。
  List<String> enabledPeerUris() =>
      enabledPeers().map((p) => p.uri).toList(growable: false);

  String _escapeString(String s) =>
      s.replaceAll('\\', r'\\').replaceAll('"', r'\"');

  String? _normalizeFullUri(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
    if (!hasScheme) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    final path = (uri.path.isEmpty || uri.path == '/') ? '' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
    return '$scheme://$host$portPart$path$query$fragment';
  }

  Uint8List _md5(List<int> bytes) {
    final d = Digest('MD5');
    return d.process(Uint8List.fromList(bytes));
  }

  String _toHex(Uint8List bytes) {
    const hex = '0123456789abcdef';
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(hex[b >> 4]);
      buffer.write(hex[b & 0x0F]);
    }
    return buffer.toString();
  }

  bool _isValidCidrLike(String route) {
    final parts = route.split('/');
    if (parts.length != 2) return false;
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) return false;
    return RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(parts[0]);
  }
}
