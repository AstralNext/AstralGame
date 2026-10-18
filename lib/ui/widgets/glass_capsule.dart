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
  });

  /// 胶囊内的高光描边、模糊与阴影参数，供各处玻璃件保持一致。
  static const blurSigma = 18.0;
  static const shadowBlur = 24.0;
  static const shadowOffset = Offset(0, 10);

  final Widget child;

  /// 胶囊圆角；一般取高度的一半。
  final BorderRadius radius;

  /// 自定义玻璃底色；默认跟随主题卡片色。
  final Color? color;

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
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: glassColor,
              borderRadius: radius,
              border: Border.all(color: rimColor, width: 0.8),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
