/// 应用主题标识（Morandi / Ins 配色，已精简去重）。
enum AppThemeId {
  /// 默认：奶白 + 奶茶棕
  insCream,
  /// 浅绿 + 鼠尾草
  elegantGreen,
  /// 雾白 + 灰蓝
  mistBlue,
  /// 淡紫 + 薰衣草
  lavenderGrey,
  /// 浅灰 + 中性灰
  cementGrey,
  /// 深色 + 金棕
  darkCoffee,
  /// 赛博朋克 2077：深空底 + 霓虹黄青
  cyber2077,
}

extension AppThemeIdCodec on AppThemeId {
  static const int _legacyThemeCount = 11;

  String get label => switch (this) {
        AppThemeId.insCream => '奶油',
        AppThemeId.elegantGreen => '淡雅绿',
        AppThemeId.mistBlue => '雾蓝',
        AppThemeId.lavenderGrey => '薰衣草',
        AppThemeId.cementGrey => '水泥灰',
        AppThemeId.darkCoffee => '黑咖',
        AppThemeId.cyber2077 => '2077',
      };

  String get subtitle => switch (this) {
        AppThemeId.insCream => '奶白背景 · 奶茶棕强调',
        AppThemeId.elegantGreen => '浅绿背景 · 鼠尾草绿强调',
        AppThemeId.mistBlue => '雾白底 · 灰蓝强调',
        AppThemeId.lavenderGrey => '淡紫底 · 薰衣草强调',
        AppThemeId.cementGrey => '浅灰底 · 中性灰强调',
        AppThemeId.darkCoffee => '深灰底 · 金棕点缀',
        AppThemeId.cyber2077 => '深空底 · 霓虹黄青点缀',
      };

  static AppThemeId fromIndex(int index) {
    if (index < 0 || index >= AppThemeId.values.length) {
      return AppThemeId.insCream;
    }
    return AppThemeId.values[index];
  }

  /// schema 1 存储序号到当前主题的映射。
  static AppThemeId fromLegacyIndex(int legacyIndex) {
    if (legacyIndex < 0 || legacyIndex >= _legacyThemeCount) {
      return AppThemeId.insCream;
    }
    return _fromLegacyIndex(legacyIndex);
  }

  static AppThemeId _fromLegacyIndex(int legacyIndex) => switch (legacyIndex) {
        0 => AppThemeId.insCream,
        1 => AppThemeId.elegantGreen,
        // 蜜桃 / 燕麦 / 落日杏 / 米灰宣纸 → 默认暖色
        2 || 3 || 4 || 8 => AppThemeId.insCream,
        5 => AppThemeId.mistBlue,
        6 => AppThemeId.lavenderGrey,
        7 => AppThemeId.cementGrey,
        9 => AppThemeId.darkCoffee,
        // 脏粉 → 薰衣草（最接近的冷粉紫）
        10 => AppThemeId.lavenderGrey,
        _ => AppThemeId.insCream,
      };

  int get storageIndex => AppThemeId.values.indexOf(this);
}
