import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/utils/net_addr.dart';

/// 房间内某条「开放游戏」宣告（自己或同伴经 ET 发来）。
class OpenGameListing {
  const OpenGameListing({
    required this.key,
    required this.fromPeerId,
    required this.ownerName,
    required this.roomGameId,
    required this.adId,
    required this.label,
    required this.ipv4,
    required this.port,
    this.motd,
    required this.expiresAt,
    this.isSelf = false,
    this.isRoomHost = false,
  });

  /// 去重键：`peerId:adId`。
  final String key;
  final int fromPeerId;
  final String ownerName;
  final String roomGameId;
  final String adId;
  final String label;
  final String ipv4;
  final int port;
  final String? motd;
  final DateTime expiresAt;
  final bool isSelf;
  final bool isRoomHost;

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

  OpenGameListing copyWith({
    String? ownerName,
    DateTime? expiresAt,
    bool? isRoomHost,
  }) {
    return OpenGameListing(
      key: key,
      fromPeerId: fromPeerId,
      ownerName: ownerName ?? this.ownerName,
      roomGameId: roomGameId,
      adId: adId,
      label: label,
      ipv4: ipv4,
      port: port,
      motd: motd,
      expiresAt: expiresAt ?? this.expiresAt,
      isSelf: isSelf,
      isRoomHost: isRoomHost ?? this.isRoomHost,
    );
  }
}

/// 本机即将经 ET 发出的开放游戏快照。
class LocalOpenGameAd {
  const LocalOpenGameAd({
    required this.entry,
    required this.ipv4,
    required this.roomGameId,
    required this.port,
    required this.label,
    this.motd,
  });

  final GameAssistLanGameDiscoverEntry entry;
  final String ipv4;
  final String roomGameId;
  final int port;
  final String label;
  final String? motd;

  Map<String, dynamic> toWire() => {
        'adId': '${entry.id}:$port',
        'gameId': roomGameId,
        'label': label,
        'ipv4': ipv4,
        'port': port,
        if (motd != null && motd!.isNotEmpty) 'motd': motd,
      };
}
