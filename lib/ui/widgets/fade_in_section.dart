import 'package:astral_game/config/app_dimensions.dart';
import 'package:flutter/material.dart';

/// 进场动效：透明度 + 轻微上移，多段 [order] 错开节奏。
class FadeInSection extends StatelessWidget {
  const FadeInSection({
    super.key,
    required this.child,
    this.order = 0,
    this.baseDelay = const Duration(
      milliseconds: AppDimensions.fadeBaseDelayMs,
    ),
    this.duration = const Duration(
      milliseconds: AppDimensions.fadeDurationMs,
    ),
    this.offsetY = 12,
  });

  final Widget child;
  final int order;
  final Duration baseDelay;
  final Duration duration;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    final delay = baseDelay * order;
    final total = duration + delay;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final ratio = total.inMilliseconds == 0
            ? 1.0
            : ((t * total.inMilliseconds - delay.inMilliseconds) /
                    duration.inMilliseconds)
                .clamp(0.0, 1.0);
        return Opacity(
          opacity: ratio,
          child: Transform.translate(
            offset: Offset(0, (1 - ratio) * offsetY),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
