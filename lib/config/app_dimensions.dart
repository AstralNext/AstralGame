/// 页面边距、分区间距与列表项内边距。
abstract final class AppDimensions {
  static const radiusSm = 16.0;
  static const radiusMd = 18.0;
  static const radiusLg = 20.0;

  static const pagePaddingH = 24.0;
  static const pagePaddingV = 20.0;
  static const sectionGap = 16.0;

  /// 窄屏（手机）左右边距，给内容更多横向空间。
  static const pagePaddingHMobile = 16.0;

  /// 页面底部留白。
  static const pagePaddingBottom = 24.0;

  /// 悬浮胶囊底栏占用的高度（胶囊 64 + 上下浮起间隙 20）。
  static const navBarClearance = 84.0;

  /// 有悬浮底栏时，滚动内容末尾需要预留的底部留白，保证最后一项能滚到胶囊上方。
  static const listBottomWithNav = navBarClearance;

  /// 有 FAB 时列表底部需要额外让出的高度。
  static const listBottomWithFab = 88.0;

  /// 可点击图标按钮的最小触控区域（Material 规范 48，视觉 40）。
  static const iconButtonSize = 40.0;

  static const iconSize = 22.0;

  static const fadeBaseDelayMs = 60;
  static const fadeDurationMs = 250;
}

/// 全站统一断点，避免各页面各写一套魔法数字。
abstract final class AppBreakpoints {
  /// 窄屏 / 宽屏分界（手机与桌面布局切换）。
  static const narrow = 600.0;
}
