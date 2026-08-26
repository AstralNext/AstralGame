import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/utils/net_addr.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'open_game_listing.freezed.dart';

/// 房间内某条「开放游戏」宣告（自己或同伴经 ET 发来）。
@freezed
abstract class OpenGameListing with _$OpenGameListing {
  const OpenGameListing._();
  const factory OpenGameListing({
    /// 去重键：`peerId:adId`。
    required final String key,
    required final int fromPeerId,
    required final String ownerName,
    required final String roomGameId,
    required final String adId,
    required final String label,
    required final String ipv4,
    required final int port,
    final String? motd,
    required final DateTime expiresAt,
    @Default(false) final bool isSelf,
    @Default(false) final bool isRoomHost,
  }) = _OpenGameListing;

  String get endpoint => '$ipv4:$port';

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toWire() => {
        'adId': adId,
        'gameId': roomGameId,
        'label': label,
        'ipv4': ipv4,
        'port': port,
        if (motd != null && motd!.isNotEmpty) 'motd': motd,
      };

  static OpenGameListing? fromWire({
    required int fromPeerId,
    required String ownerName,
    required Map<String, dynamic> raw,
    required int ttlMs,
    required bool isSelf,
    required bool isRoomHost,
  }) {
    final adId = '${raw['adId'] ?? raw['id'] ?? ''}'.trim();
    final ipv4 = stripIpv4Host('${raw['ipv4'] ?? ''}') ?? '';
    final port = (raw['port'] as num?)?.toInt() ?? 0;
    final gameId = '${raw['gameId'] ?? ''}'.trim();
    if (adId.isEmpty || ipv4.isEmpty || port <= 0) return null;
    return OpenGameListing(
      key: '$fromPeerId:$adId',
      fromPeerId: fromPeerId,
      ownerName: ownerName,
      roomGameId: gameId,
      adId: adId,
      label: '${raw['label'] ?? '开放游戏'}'.trim().isEmpty
          ? '开放游戏'
          : '${raw['label'] ?? '开放游戏'}'.trim(),
      ipv4: ipv4,
      port: port,
      motd: raw['motd']?.toString(),
      expiresAt: DateTime.now().add(Duration(milliseconds: ttlMs.clamp(3000, 120000))),
      isSelf: isSelf,
      isRoomHost: isRoomHost,
    );
  }
}

/// 本机即将经 ET 发出的开放游戏快照。
@freezed
abstract class LocalOpenGameAd with _$LocalOpenGameAd {
  const factory LocalOpenGameAd({
    required final GameAssistLanGameDiscoverEntry entry,
    required final String ipv4,
    required final String roomGameId,
    required final int port,
    required final String label,
    final String? motd,
  }) = _LocalOpenGameAd;
}

extension LocalOpenGameAdWire on LocalOpenGameAd {
  Map<String, dynamic> toWire() => {
        'adId': '${entry.id}:$port',
        'gameId': roomGameId,
        'label': label,
        'ipv4': ipv4,
        'port': port,
        if (motd != null && motd!.isNotEmpty) 'motd': motd,
      };
}
