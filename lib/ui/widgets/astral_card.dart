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

    if (onTap != null || onLongPress != null) {
      inner = Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          splashColor: palette.accentMuted,
          highlightColor: palette.accent.withValues(alpha: 0.08),
          child: inner,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: palette.shadowSoft,
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: inner,
      ),
    );
  }
}
