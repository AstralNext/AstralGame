/// 应用主题标识（Morandi / Ins 配色）。
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

  int get storageIndex => AppThemeId.values.indexOf(this);
}
