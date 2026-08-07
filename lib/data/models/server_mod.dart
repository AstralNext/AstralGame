class ServerMod {
  final int id;
  final String name;
  final String url;
  final bool enable;

  /// 排序顺序
  final int sortOrder;

  static int _nextId = 1;

  static void setNextId(int value) {
    _nextId = value;
  }

  /// 获取下一个唯一 ID
  static int generateNextId() {
    return _nextId++;
  }

  ServerMod({
    int? id,
    this.enable = false,
    required this.name,
    required this.url,
    this.sortOrder = 0,
  }) : id = id ?? generateNextId();

  ServerMod copyWith({
    String? name,
    String? url,
    bool? enable,
    int? sortOrder,
  }) {
    return ServerMod(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      enable: enable ?? this.enable,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'enable': enable,
        'sortOrder': sortOrder,
      };

  factory ServerMod.fromJson(Map<String, dynamic> json) => ServerMod(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        enable: json['enable'] as bool? ?? false,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

/// 进网 peer 条目（TOML `[[peer]]` / 短码载荷）。仅 URI，不使用 peer_public_key。
class PeerEndpoint {
  const PeerEndpoint({required this.uri});

  final String uri;

  Map<String, dynamic> toJson() => {'uri': uri};

  factory PeerEndpoint.fromJson(dynamic raw) {
    if (raw is String) {
      return PeerEndpoint(uri: raw.trim());
    }
    if (raw is Map) {
      final map = raw.map((k, v) => MapEntry('$k', v));
      return PeerEndpoint(
        uri: '${map['uri'] ?? map['url'] ?? ''}'.trim(),
      );
    }
    return const PeerEndpoint(uri: '');
  }
}
