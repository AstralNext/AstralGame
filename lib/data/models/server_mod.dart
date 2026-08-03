enum ServerSource {
  manual,
  public,
}

class ServerMod {
  final int id;
  final String name;
  final String url;
  final bool enable;
  final bool encrypted;
  final ServerSource source;

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
    this.encrypted = false,
    required this.name,
    required this.url,
    this.source = ServerSource.manual,
    this.sortOrder = 0,
  }) : id = id ?? generateNextId();

  ServerMod copyWith({
    String? name,
    String? url,
    bool? enable,
    bool? encrypted,
    ServerSource? source,
    int? sortOrder,
  }) {
    return ServerMod(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      enable: enable ?? this.enable,
      encrypted: encrypted ?? this.encrypted,
      source: source ?? this.source,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'enable': enable,
        'encrypted': encrypted,
        'source': source.name,
        'sortOrder': sortOrder,
      };

  factory ServerMod.fromJson(Map<String, dynamic> json) => ServerMod(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        enable: json['enable'] as bool? ?? false,
        encrypted: json['encrypted'] as bool? ?? false,
        source: ServerSource.values.byName(
          (json['source'] as String?) ?? ServerSource.manual.name,
        ),
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}
