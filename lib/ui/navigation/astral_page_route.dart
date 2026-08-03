import 'package:astral_game/config/app_dimensions.dart';
import 'package:flutter/material.dart';

/// 二级页统一过渡：淡入 + 轻微上移（与 [FadeInSection] 节奏一致）。
PageRoute<T> astralPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration:
        const Duration(milliseconds: AppDimensions.fadeDurationMs),
    reverseTransitionDuration:
        const Duration(milliseconds: AppDimensions.fadeDurationMs),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
