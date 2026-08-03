import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/public_server_service.dart';
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

  /// 生成“房间码”（更短，适合作为分享码/房间密钥）
  ///
  /// 注意：这里用 `Random.secure()`，用于“当密码用”的场景。
  String generateRoomCode({int length = 10}) {
    const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// 启用服务器列表“指纹”（顺序无关）
  ///
  /// 用于：快速判断双方启用服务器是否一致（不是机密信息）。
  /// 规则：
  /// - 只取启用服务器的“完整 URI”
  /// - 去空格、做基础规范化
  /// - 排序后拼接，再计算 MD5，最后截断为短串
  String enabledServersFingerprint({int length = 8}) {
    final enabledServers = _serverState.getEnabledServers();
    final normalizedUris =
        enabledServers
            .map((server) {
              final url = server.encrypted
                  ? _decryptUrl(server.url) ?? server.url
                  : server.url;
              return _normalizeFullUri(url);
            })
            .whereType<String>()
            .where((u) => u.isNotEmpty)
            .toList()
          ..sort();

    final joined = normalizedUris.join('\n');
    final digestBytes = _md5(utf8.encode(joined));
    final hex = _toHex(digestBytes);
    if (length <= 0) return '';
    return hex.substring(0, length.clamp(1, hex.length));
  }

  /// 构建房间分享码：`随机码_房间名`
  String buildRoomShareCode({
    required String roomName,
    required String token,
  }) {
    final safeToken = token.trim();
    final safeRoomName = roomName.trim();
    return '${safeToken}_$safeRoomName';
  }

  /// 将任意已存分享码规范为 `随机码_房间名`（复制到剪贴板用）。
  String normalizeRoomShareCode(String shareCode) {
    final parts = parseRoomShareCode(shareCode);
    if (parts == null) return shareCode.trim();
    return buildRoomShareCode(
      roomName: parts.roomName,
      token: parts.token,
    );
  }

  static final _shareTokenPattern = RegExp(
    r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz]{6,20}$',
  );

  /// 解析房间分享码：`随机码_房间名`（房间名可含 `_`）。
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

  /// 构建 TOML 配置文件
  String buildTomlConfig(String roomName, String roomPassword) {
    final disableP2p = _appSettings.isDisableP2p();
    final enabledServers = _serverState.getEnabledServers();

    // EasyTier hostname：优先用户名，空则用 "Astral"。
    final rawUsername = _appSettings.getUsername().trim();
    final hostname = rawUsername.isEmpty ? 'Astral' : rawUsername;

    String peerBlock = '';
    if (enabledServers.isNotEmpty) {
      peerBlock = enabledServers
          .map((server) {
            final url = server.encrypted
                ? _decryptUrl(server.url) ?? server.url
                : server.url;

            // 服务器地址现在支持“完整 URI”（例如 tcp://host:port、udp://host:port、ws://...）
            // 如果已经带 scheme，则不要再拼装协议前缀，避免出现 tcp://tcp//... 这类错误。
            final trimmed = url.trim();
            final hasScheme = RegExp(
              r'^[a-zA-Z][a-zA-Z0-9+.-]*://',
            ).hasMatch(trimmed);
            if (hasScheme) {
              return '[[peer]]\nuri = "${_escapeString(trimmed)}"';
            }
            appLogger.w('[P2PConfigService] 跳过无效服务器地址（必须是完整 URI）: $trimmed');
            return '';
          })
          .where((s) => s.isNotEmpty)
          .join('\n\n');
    }

    final proxyBlock = _vpnState.customRoutes.value
        .map((route) => route.trim())
        .where(_isValidCidrLike)
        .map((route) => '[[proxy_network]]\ncidr = "${_escapeString(route)}"')
        .join('\n\n');

    // 与 EasyTier `TomlConfigLoader::gen_flags` 合并用的 JSON 键一致（Rust 字段 snake_case）。
    final udpBroadcastFlag =
        RuntimePlatform.operatingSystem == 'windows' &&
            _appSettings.isEnableUdpBroadcastRelay()
        ? 'enable_udp_broadcast_relay = true\n'
        : '';

    appLogger.i(
      '[P2PConfigService] buildTomlConfig room=$roomName '
      'disable_p2p=$disableP2p peers=${enabledServers.length}',
    );

    return '''
instance_name = "AstralGame"
hostname = "${_escapeString(hostname)}"
dhcp = true
listeners = [
    "tcp://0.0.0.0:0",
    "udp://0.0.0.0:0",
] 

[network_identity]
network_name = "${_escapeString(roomName)}" 
network_secret = "${_escapeString(roomPassword)}" 

${peerBlock.isNotEmpty ? '$peerBlock\n\n' : ''}${proxyBlock.isNotEmpty ? '$proxyBlock\n\n' : ''}[flags]
disable_p2p = $disableP2p
$udpBroadcastFlag
''';
  }

  /// 转义字符串中的特殊字符
  String _escapeString(String s) =>
      s.replaceAll('\\', r'\\').replaceAll('"', r'\"');

  /// 解密加密的服务器 URL
  String? _decryptUrl(String encryptedUrl) {
    return PublicServerService().decryptUrl(encryptedUrl);
  }

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
