import 'package:flutter/widgets.dart';

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

  /// 桌面侧栏总宽（悬浮胶囊 + 左右留白），与 [LeftNav] 保持一致。
  static const sideNavWidth = 92.0;

  /// 悬浮胶囊底栏的高度（与 BottomNav 保持一致）。
  static const navBarHeight = 64.0;

  /// 胶囊底栏内部的上下留白（与 BottomNav 的内边距保持一致）。
  static const navBarPadding = 10.0;

  /// 悬浮底栏距屏幕底边的留白。
  ///
  /// 手势导航的系统安全区较高，整段让出会让胶囊离底边太远；
  /// 这里只保留一点呼吸位，把多余的安全区压掉。三键导航仍需完整让出。
  static double navBottomGap(BuildContext context) {
    // 必须用 viewPadding：Scaffold 在 extendBody 时会把底栏高度
    // 写进 body 的 padding.bottom，用 padding 会把自己算进去（90/164）。
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return inset >= 40 ? inset : 12;
  }

  /// 有悬浮底栏时，滚动内容末尾需要预留的底部留白。
  ///
  /// 留到胶囊上沿，再多留 [navContentGap]，最后一项不会贴死胶囊。
  static double listBottomWithNav(BuildContext context) =>
      navBottomGap(context) + navBarPadding + navBarHeight + navContentGap;

  /// 内容末尾与胶囊上沿之间的呼吸位。
  static const navContentGap = 12.0;

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
