import 'dart:math' as math;

import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/state/theme_reveal_state.dart';
import 'package:astral_game/di.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 根级包裹：新主题在底层，旧主题色以「反圆形裁剪」从点击处被水滴撑开。
class ThemeWaterDropHost extends StatefulWidget {
  const ThemeWaterDropHost({super.key, required this.child});

  final Widget child;

  @override
  State<ThemeWaterDropHost> createState() => _ThemeWaterDropHostState();
}

class _ThemeWaterDropHostState extends State<ThemeWaterDropHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final EffectCleanup _revealEffect;
  ThemeRevealState? _animatingReveal;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppThemeAnimation.revealDuration,
    )..addStatusListener(_onRevealStatus);

    _revealEffect = effect(() {
      final reveal = getIt<ThemeRevealController>().reveal.value;
      if (reveal.isActive && mounted) {
        _startReveal(reveal);
      }
    });
  }

  void _onRevealStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    getIt<ThemeRevealController>().finishReveal();
    if (mounted) {
      setState(() => _animatingReveal = null);
    }
  }

  @override
  void dispose() {
    _revealEffect();
    _controller.dispose();
    super.dispose();
  }

  void _startReveal(ThemeRevealState reveal) {
    if (_controller.isAnimating) {
      _controller.stop();
    }
    setState(() => _animatingReveal = reveal);
    _controller
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final animating = _animatingReveal;
    final showOverlay =
        animating != null && animating.isActive && animating.origin != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showOverlay && animating.previousThemeId != null)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final size = MediaQuery.sizeOf(context);
                  final origin = animating.origin!;
                  final maxR = _maxRevealRadius(origin, size);
                  final t =
                      AppThemeAnimation.revealCurve.transform(_controller.value);
                  final radius = maxR * t;
                  final palette =
                      AppThemePalette.of(animating.previousThemeId!);

                  return ClipPath(
                    clipper: _InverseCircleClipper(
                      center: origin,
                      radius: radius,
                    ),
                    child: ColoredBox(
                      color: palette.background,
                      child: CustomPaint(
                        painter: _WaterDropEdgePainter(
                          center: origin,
                          radius: radius,
                          edgeColor: palette.accent.withValues(alpha: 0.22),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  );
                },
              ),
              ),
            ),
          ),
      ],
    );
  }
}

double _maxRevealRadius(Offset origin, Size size) {
  var maxDist = 0.0;
  for (final corner in [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
  ]) {
    maxDist = math.max(maxDist, (corner - origin).distance);
  }
  return maxDist + 8;
}

class _InverseCircleClipper extends CustomClipper<Path> {
  _InverseCircleClipper({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) {
    final rect = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    return Path.combine(PathOperation.difference, rect, hole);
  }

  @override
  bool shouldReclip(covariant _InverseCircleClipper oldClipper) =>
      oldClipper.radius != radius || oldClipper.center != center;
}

class _WaterDropEdgePainter extends CustomPainter {
  _WaterDropEdgePainter({
    required this.center,
    required this.radius,
    required this.edgeColor,
  });

  final Offset center;
  final double radius;
  final Color edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;

    final paint = Paint()
      ..color = edgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _WaterDropEdgePainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.center != center ||
      oldDelegate.edgeColor != edgeColor;
}
