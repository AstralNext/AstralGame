/// [name] 为展示名；[roomName] 为 EasyTier `network_name`（分享码里 `_` 后一段）。
///
/// [password] 仅保留兼容字段，加入历史不落盘密钥（读写恒为空）。
class RoomMod {
  final int id;
  final String name;
  final String roomName;
  final String host;
  final int port;
  final String password;
  final String shareCode;
  final DateTime createdAt;

  const RoomMod({
    required this.id,
    required this.name,
    required this.roomName,
    required this.host,
    required this.port,
    this.password = '',
    required this.shareCode,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'room_name': roomName,
        'host': host,
        'port': port,
        // 故意不写密钥：历史 JSON 里的 password 一律清空。
        'password': '',
        'share_code': shareCode,
        'created_at': createdAt.toIso8601String(),
      };

  factory RoomMod.fromJson(Map<String, dynamic> json) => RoomMod(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        roomName: json['room_name'] as String? ?? '',
        host: json['host'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 0,
        shareCode: json['share_code'] as String? ?? '',
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}
