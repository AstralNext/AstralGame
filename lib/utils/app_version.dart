import 'dart:math';

/// 应用版本比较：去掉 `v` 前缀与 `+build`，再按 semver / pre-release 比较。
///
/// 与 Astral2 [AppVersion] 对齐，避免更新判定分叉。
class AppVersion {
  AppVersion._();

  /// 用于比较的核心串，如 `1.0.0-beta.1`。
  static String normalize(String version) {
    var s = version.trim();
    if (s.toLowerCase().startsWith('v')) {
      s = s.substring(1).trim();
    }
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    return s;
  }

  /// [candidate] 是否比 [current] 更新。
  static bool isNewer(String candidate, String current) {
    final latest = normalize(candidate);
    final curr = normalize(current);
    if (latest.isEmpty || curr.isEmpty) return false;

    final currentParts = curr.split('-');
    final latestParts = latest.split('-');

    final currentMain = _parseVersionParts(currentParts[0]);
    final latestMain = _parseVersionParts(latestParts[0]);

    for (var i = 0; i < 3; i++) {
      final c = i < currentMain.length ? currentMain[i] : 0;
      final l = i < latestMain.length ? latestMain[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }

    if (currentParts.length == 1) return latestParts.length > 1;
    if (latestParts.length == 1) return true;

    return _comparePreRelease(currentParts[1], latestParts[1]) < 0;
  }

  static List<int> _parseVersionParts(String version) {
    return version.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }

  static int _comparePreRelease(String a, String b) {
    final aParts = a.split('.');
    final bParts = b.split('.');
    for (var i = 0; i < max(aParts.length, bParts.length); i++) {
      final aVal = i < aParts.length ? aParts[i] : '';
      final bVal = i < bParts.length ? bParts[i] : '';
      final aNum = int.tryParse(aVal);
      final bNum = int.tryParse(bVal);
      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aVal.compareTo(bVal);
        if (cmp != 0) return cmp;
      }
    }
    return 0;
  }
}
