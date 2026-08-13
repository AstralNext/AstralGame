import 'dart:convert';
import 'dart:typed_data';

/// 按 JSON `parser` 重建局域网宣告载荷（与具体游戏解耦，后续只加 builder）。
typedef LanPayloadBuilder = Uint8List? Function({
  required String title,
  required int port,
});

final Map<String, LanPayloadBuilder> _lanPayloadBuilders = {
  'minecraft_motd': buildMinecraftMotdPayload,
};

LanPayloadBuilder? lanPayloadBuilderOf(String name) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  return _lanPayloadBuilders[key];
}

/// MC LAN：`[MOTD]title[/MOTD][AD]port[/AD]`
Uint8List? buildMinecraftMotdPayload({
  required String title,
  required int port,
}) {
  if (port <= 0 || port > 65535) return null;
  final motd = title.trim().isEmpty ? 'Game' : title.trim();
  return Uint8List.fromList(
    utf8.encode('[MOTD]$motd[/MOTD][AD]$port[/AD]'),
  );
}
