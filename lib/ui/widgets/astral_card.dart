import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// Material 3 卡片：无描边、轻阴影。
class AstralCard extends StatelessWidget {
  const AstralCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppDimensions.radiusMd,
    this.shadow = true,
    this.color,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool shadow;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final bg = color ?? palette.card;
    final borderRadius = BorderRadius.circular(radius);

    Widget inner = child;
    if (padding != null) {
      inner = Padding(padding: padding!, child: inner);
    }

    // 必须用 Material 承载色，不能用 DecoratedBox 填色：否则内部 ListTile
    // 的 ink 画在更上层 Material 上会被挡住，debug 下狂抛异常导致卡顿。
    Widget card;
    if (onTap != null || onLongPress != null) {
      card = Material(
        color: bg,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          splashColor: palette.accentMuted,
          highlightColor: palette.accent.withValues(alpha: 0.08),
          child: inner,
        ),
      );
    } else {
      card = Material(
        color: bg,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        child: inner,
      );
    }

    if (!shadow) return card;

    // 阴影单独放外层，不要带 color，避免再次挡住 ink。
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: palette.shadowSoft,
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: card,
    );
  }
}
