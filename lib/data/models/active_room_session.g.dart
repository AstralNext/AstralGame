// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_room_session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RoomInvitePayload _$RoomInvitePayloadFromJson(Map<String, dynamic> json) =>
    _RoomInvitePayload(
      v: (json['v'] as num?)?.toInt() ?? 1,
      gameId: json['game_id'] as String,
      gameName: json['game_name'] as String,
      networkName: json['network_name'] as String,
      networkSecret: json['network_secret'] as String,
      peers: (json['peers'] as List<dynamic>)
          .map((e) => PeerEndpoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      displayName: json['display_name'] as String?,
    );

Map<String, dynamic> _$RoomInvitePayloadToJson(_RoomInvitePayload instance) =>
    <String, dynamic>{
      'v': instance.v,
      'game_id': instance.gameId,
      'game_name': instance.gameName,
      'network_name': instance.networkName,
      'network_secret': instance.networkSecret,
      'peers': instance.peers.map((e) => e.toJson()).toList(),
      'display_name': instance.displayName,
    };
