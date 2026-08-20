import 'package:astral_game/data/models/server_mod.dart';

const Object _unset = Object();

/// 短码 / 离线邀请载荷：共享 network_name + network_secret（旧版进网方式）。
class RoomInvitePayload {
  const RoomInvitePayload({
    this.v = 1,
    required this.gameId,
    required this.gameName,
    required this.networkName,
    required this.networkSecret,
    required this.peers,
    this.displayName,
  });

  final int v;
  final String gameId;
  final String gameName;
  final String networkName;
  final String networkSecret;
  final List<PeerEndpoint> peers;
  final String? displayName;

  Map<String, dynamic> toJson() => {
        'v': v,
        'game_id': gameId,
        'game_name': gameName,
        'network_name': networkName,
        'network_secret': networkSecret,
        'peers': [for (final p in peers) p.toJson()],
        if (displayName != null && displayName!.isNotEmpty)
          'display_name': displayName,
      };

  factory RoomInvitePayload.fromJson(Map<String, dynamic> json) {
    final peersRaw = json['peers'];
    final peers = <PeerEndpoint>[];
    if (peersRaw is List) {
      for (final e in peersRaw) {
        final peer = PeerEndpoint.fromJson(e);
        if (peer.uri.isNotEmpty) peers.add(peer);
      }
    }
    return RoomInvitePayload(
      v: (json['v'] as num?)?.toInt() ?? 1,
      gameId: '${json['game_id'] ?? ''}',
      gameName: '${json['game_name'] ?? ''}',
      networkName: '${json['network_name'] ?? ''}',
      networkSecret: '${json['network_secret'] ?? ''}',
      peers: peers,
      displayName: json['display_name']?.toString(),
    );
  }
}

/// 房主暂时退出后可恢复的快照（内存，不落盘）。
class HostResumeSnapshot {
  const HostResumeSnapshot({
    required this.gameId,
    required this.gameName,
    required this.networkName,
    required this.networkSecret,
    required this.displayName,
  });

  final String gameId;
  final String gameName;
  final String networkName;
  final String networkSecret;
  final String displayName;

  factory HostResumeSnapshot.fromSession(ActiveRoomSession session) {
    return HostResumeSnapshot(
      gameId: session.gameId,
      gameName: session.gameName,
      networkName: session.networkName,
      networkSecret: session.networkSecret,
      displayName: session.displayName,
    );
  }
}

/// 当前内存会话（不落盘）。
class ActiveRoomSession {
  const ActiveRoomSession({
    required this.isHost,
    required this.gameId,
    required this.gameName,
    required this.networkName,
    required this.networkSecret,
    required this.displayName,
    this.shortCode,
    this.adminToken,
  });

  final bool isHost;
  final String gameId;
  final String gameName;
  final String networkName;
  final String networkSecret;
  final String displayName;
  final String? shortCode;
  /// 短码服务管理令牌（作废短码用），与进网无关。
  final String? adminToken;

  String get roleLabel => isHost ? '房主' : '成员';

  ActiveRoomSession copyWith({
    Object? shortCode = _unset,
    Object? adminToken = _unset,
  }) {
    return ActiveRoomSession(
      isHost: isHost,
      gameId: gameId,
      gameName: gameName,
      networkName: networkName,
      networkSecret: networkSecret,
      displayName: displayName,
      shortCode: identical(shortCode, _unset)
          ? this.shortCode
          : shortCode as String?,
      adminToken: identical(adminToken, _unset)
          ? this.adminToken
          : adminToken as String?,
    );
  }
}

/// 加入房间前校验载荷，并返回可用的服务器列表。
List<PeerEndpoint> joinableInvitePeers(RoomInvitePayload payload) {
  if (payload.networkSecret.isEmpty) {
    throw StateError('邀请无效：缺少房间密码（请让房主用新版重新分享）');
  }
  final peers = [
    for (final p in payload.peers)
      if (p.uri.trim().isNotEmpty) p,
  ];
  if (peers.isEmpty) {
    throw StateError('邀请未包含服务器，无法加入（请让房主启用服务器后重新分享）');
  }
  return peers;
}
