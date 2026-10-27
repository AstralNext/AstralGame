import 'dart:ui' as ui;

import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// 液态玻璃胶囊底座：磨砂底 + 前景虚化 + 高光描边 + 柔和投影。
///
/// 阴影画在圆角裁剪之外，所以父级不要再用会裁剪的组件包住它，
/// 否则阴影会被裁成一块方形，看起来像胶囊被关在盒子里。
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({
    super.key,
    required this.child,
    required this.radius,
    this.color,
    this.sigma = blurSigma,
  });

  /// 胶囊内的高光描边、模糊与阴影参数，供各处玻璃件保持一致。
  static const blurSigma = 18.0;

  /// 宽度动画进行中使用的较低模糊值，减少每帧重新采样背景的开销。
  static const animatingBlurSigma = 10.0;
  static const shadowBlur = 24.0;
  static const shadowOffset = Offset(0, 10);

  final Widget child;

  /// 胶囊圆角；一般取高度的一半。
  final BorderRadius radius;

  /// 自定义玻璃底色；默认跟随主题卡片色。
  final Color? color;

  /// 背景模糊半径；尺寸动画期间可临时调低。
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 深色主题更透一些，让下方内容隐约透出来。
    final glassColor =
        color ?? palette.card.withValues(alpha: isDark ? 0.62 : 0.78);
    final rimColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.85);
    // 左上到右下的极轻渐变，让一整块玻璃有厚度，而不是纯色贴纸。
    final sheenTop = Color.lerp(glassColor, Colors.white, isDark ? 0.08 : 0.26)!;
    final sheenBottom = Color.lerp(
      glassColor,
      Colors.black,
      isDark ? 0.10 : 0.02,
    )!;

    final glass = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [sheenTop, glassColor, sheenBottom],
          stops: const [0, 0.58, 1],
        ),
        borderRadius: radius,
        border: Border.all(color: rimColor, width: 0.8),
      ),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: palette.shadowSoft,
            blurRadius: shadowBlur,
            offset: shadowOffset,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        // 玻璃是静态层时缓存一次；避免每次父级重绘都重新做一次背景模糊。
        child: RepaintBoundary(
          child: sigma <= 0
              ? glass
              : BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: glass,
                ),
        ),
      ),
    );
  }
}
