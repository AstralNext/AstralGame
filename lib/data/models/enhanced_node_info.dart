import 'dart:typed_data';

import 'package:astral_game/utils/net_addr.dart';
import 'package:astral_rust_core/p2p_service.dart' show KVNodeInfo;

/// 在 [`KVNodeInfo`] 上叠加 peer-RPC（`user.getInfo`）返回的昵称与头像等资料。
class EnhancedNodeInfo {
  final KVNodeInfo baseInfo;
  final Map<String, dynamic> metadata;
  final String? customName;
  final Uint8List? avatar;

  EnhancedNodeInfo({
    required this.baseInfo,
    this.metadata = const {},
    this.customName,
    this.avatar,
  });

  factory EnhancedNodeInfo.fromKVNodeInfo(KVNodeInfo info) {
    return EnhancedNodeInfo(baseInfo: info);
  }

  EnhancedNodeInfo copyWith({
    KVNodeInfo? baseInfo,
    Map<String, dynamic>? metadata,
    String? customName,
    Uint8List? avatar,
    bool clearAvatar = false,
  }) {
    return EnhancedNodeInfo(
      baseInfo: baseInfo ?? this.baseInfo,
      metadata: metadata ?? this.metadata,
      customName: customName ?? this.customName,
      avatar: clearAvatar ? null : (avatar ?? this.avatar),
    );
  }

  int get peerId => baseInfo.peerId;
  String get hostname => baseInfo.hostname;
  String get ipv4 => baseInfo.ipv4;
  /// 虚拟网 IPv6（通常带 `/prefix`），无则为空串。
  String get ipv6 => baseInfo.ipv6;
  String get displayName => customName ?? baseInfo.hostname;
  String get remoteStaticPubkeyB64 => baseInfo.remoteStaticPubkeyB64;
  bool get isCredentialPeer => baseInfo.isCredentialPeer;

  /// 对端 `user.getInfo` 上报的 `os`（如 `windows` / `android`）。
  String? get peerOs => metadata['peerOs'] as String?;

  /// 对端系统版本（各平台格式不同，与对端 `Platform.operatingSystemVersion` 一致）。
  String? get peerOsVersion => metadata['peerOsVersion'] as String?;

  /// 对端应用名（对端 PackageInfo.appName）。
  String? get peerAppName => metadata['peerAppName'] as String?;

  /// 对端应用版本（如 `1.0.0+1`）。
  String? get peerAppVersion => metadata['peerAppVersion'] as String?;

  /// 对端网络承载类型 wire 值（`wifi` / `ethernet` / `mobile` / `bluetooth` / `satellite` / `other` / `none` 等）。
  /// 见 [`NetworkKind`]；UI 通过 [`NetworkPresentation.fromWire`] 解析为图标 + 文案。
  String? get peerNetwork => metadata['peerNetwork'] as String?;

  /// 对端 Windows 专用防火墙：`enabled` / `disabled` / `unsupported`。
  String? get peerFirewall => metadata['peerFirewall'] as String?;

  /// 对端头像内容 hash；无头像或尚未拉取时为空。
  String? get peerAvatarHash {
    final raw = metadata['avatarHash']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  /// 节点是否拥有有效的虚拟网 IPv4（兼容 CIDR：`x.x.x.x/24`）。
  /// 公共服务器、未分配 IP 的节点会返回 `false`。UI 用它决定"IP 文字是否高亮"。
  bool get hasValidIpv4 => stripIpv4Host(baseInfo.ipv4) != null;

  /// 节点是否拥有有效的虚拟网 IPv6（兼容 CIDR）。
  bool get hasValidIpv6 =>
      stripCidrHost(baseInfo.ipv6, unspecified: const {'::'}) != null;
}
