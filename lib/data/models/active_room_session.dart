import 'package:astral_game/data/models/server_mod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'active_room_session.freezed.dart';
part 'active_room_session.g.dart';

/// 短码 / 离线邀请载荷：共享 network_name + network_secret（旧版进网方式）。
@freezed
abstract class RoomInvitePayload with _$RoomInvitePayload {
  const RoomInvitePayload._();

  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true)
  const factory RoomInvitePayload({
    @Default(1) final int v,
    @JsonKey(name: 'game_id') required final String gameId,
    @JsonKey(name: 'game_name') required final String gameName,
    @JsonKey(name: 'network_name') required final String networkName,
    @JsonKey(name: 'network_secret') required final String networkSecret,
    required final List<PeerEndpoint> peers,
    @JsonKey(name: 'display_name') final String? displayName,

    /// 传输方式：`easytier`（EasyTier 组网，默认）/ `steam`（SDR 虚拟局域网组网）
    /// / `pear`（Holepunch HyperDHT 组网）。
    @JsonKey(name: 'transport') @Default('easytier') final String transport,

    /// Steam 模式下房主的 SteamID（客机据此建立 P2P 连接）。
    @JsonKey(name: 'host_steam_id') final String? hostSteamId,

    /// Pear 模式下房主的 HyperDHT 公钥（十六进制，客机据此建立打洞连接）。
    @JsonKey(name: 'host_pear_key') final String? hostPearKey,
  }) = _RoomInvitePayload;

  factory RoomInvitePayload.fromJson(Map<String, dynamic> json) =>
      _$RoomInvitePayloadFromJson(json);

  bool get isSteamTransport => transport == 'steam';

  bool get isPearTransport => transport == 'pear';
}

const Object _unset = Object();

/// 当前内存会话（不落盘）。
@freezed
abstract class ActiveRoomSession with _$ActiveRoomSession {
  const ActiveRoomSession._();
  const factory ActiveRoomSession({
    required final bool isHost,
    required final String gameId,
    required final String gameName,
    required final String networkName,
    required final String networkSecret,
    required final String displayName,
    final String? shortCode,
    required final List<PeerEndpoint> peers,

    /// 传输方式：`easytier`（默认）/ `steam` / `pear`。
    @Default('easytier') final String transport,
    final String? hostSteamId,

    /// Pear 模式下房主的 HyperDHT 公钥（十六进制）。
    final String? hostPearKey,
  }) = _ActiveRoomSession;

  bool get isSteamTransport => transport == 'steam';

  bool get isPearTransport => transport == 'pear';

  /// 支持显式传 null。用 [_unset] 哨兵和"用户未传参"区分。
  ActiveRoomSession copyWithNullable({Object? shortCode = _unset}) {
    return copyWith(
      shortCode: identical(shortCode, _unset)
          ? this.shortCode
          : shortCode as String?,
    );
  }
}

/// 加入房间前校验载荷，并返回可用的服务器列表。
List<PeerEndpoint> joinableInvitePeers(RoomInvitePayload payload) {
  if (payload.networkSecret.isEmpty) {
    throw StateError('邀请无效：缺少房间密码（请让分享者用新版重新分享）');
  }
  final peers = [
    for (final p in payload.peers)
      if (p.uri.trim().isNotEmpty) p,
  ];
  if (peers.isEmpty && !payload.isSteamTransport && !payload.isPearTransport) {
    throw StateError('邀请未包含服务器，无法加入（请让分享者启用服务器后重新分享）');
  }
  return peers;
}
