import 'package:astral_game/config/theme.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/ui/shell/shell.dart';
import 'package:astral_game/ui/widgets/floating_overlay_binder.dart';
import 'package:astral_game/ui/widgets/home_widget_refresh_binder.dart';
import 'package:astral_game/ui/widgets/theme_water_drop_overlay.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class AstralGameApp extends StatefulWidget {
  const AstralGameApp({super.key});

  @override
  State<AstralGameApp> createState() => _AstralGameAppState();
}

class _AstralGameAppState extends State<AstralGameApp> with WidgetsBindingObserver {
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _safeDisposeDI();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _safeDisposeDI();
    }
  }

  void _safeDisposeDI() {
    if (!_disposed) {
      _disposed = true;
      disposeDI();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = getIt<SettingsState>();

    return Watch((context) {
      final theme = AstralGameTheme.build(settingsState.appThemeId.value);

      return MaterialApp(
        title: 'Astral Game',
        debugShowCheckedModeBanner: false,
        theme: theme,
        themeAnimationDuration: AppThemeAnimation.duration,
        themeAnimationCurve: AppThemeAnimation.curve,
        builder: (context, child) => FloatingOverlayBinder(
          child: HomeWidgetRefreshBinder(
            child: ThemeWaterDropHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
        home: const Shell(),
      );
    });
  }
}
