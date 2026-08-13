/// 局域网宣告标题模板：`{player}` `{game}` `{label}` `{motd}` `{map}`。
String applyLanTitleTemplate(
  String template, {
  required String player,
  required String game,
  String label = '',
  String motd = '',
  String map = '',
}) {
  var out = template.trim();
  if (out.isEmpty) {
    final m = motd.trim();
    if (m.isNotEmpty) return m;
    final l = label.trim();
    if (l.isNotEmpty) return l;
    final p = player.trim();
    final g = game.trim();
    if (p.isNotEmpty && g.isNotEmpty) return '$p · $g';
    if (g.isNotEmpty) return g;
    return p;
  }
  out = out
      .replaceAll('{player}', player.trim())
      .replaceAll('{game}', game.trim())
      .replaceAll('{label}', label.trim())
      .replaceAll('{motd}', motd.trim())
      .replaceAll('{map}', map.trim().isNotEmpty ? map.trim() : motd.trim());
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}
