import 'package:astral_game/ui/widgets/glass_capsule.dart';
import 'package:flutter/material.dart';

/// 与悬浮底部胶囊同款磨砂玻璃圆形按钮。
///
/// 用于页面级轻量操作（刷新、添加、搜索等）；底座复用 [GlassCapsule]，
/// 让圆形按钮和胶囊使用同一套模糊、描边与阴影参数。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.size,
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.semanticsLabel,
  });

  final double size;
  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: size,
      height: size,
      child: GlassCapsule(
        radius: BorderRadius.circular(size),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Center(child: child),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      child: tooltip == null
          ? button
          : Tooltip(message: tooltip!, child: button),
    );
  }
}
