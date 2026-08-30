import 'package:astral_game/data/models/bookmark.dart';

/// Bookmark 的展示名：优先 customName，否则用 payload.gameName，再否则 networkName。
String bookmarkDisplayLabel(Bookmark b) {
  final name = b.customName.trim();
  if (name.isNotEmpty) return name;
  final game = b.payload.gameName.trim();
  if (game.isNotEmpty) return game;
  return b.payload.networkName;
}
