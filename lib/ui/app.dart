import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/services/home_widget_launch_handler.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/shell/shell.dart';
import 'package:astral_game/ui/widgets/floating_overlay_binder.dart';
import 'package:astral_game/ui/widgets/home_widget_refresh_binder.dart';
import 'package:astral_game/ui/widgets/join_link_binder.dart';
import 'package:astral_game/ui/widgets/theme_water_drop_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:signals/signals_flutter.dart';

class AstralGameApp extends StatefulWidget {
  const AstralGameApp({super.key});

  @override
  State<AstralGameApp> createState() => _AstralGameAppState();
}

class _AstralGameAppState extends State<AstralGameApp> with WidgetsBindingObserver {
  bool _disposed = false;
  final _widgetLaunchHandler = HomeWidgetLaunchHandler(
    navigation: getIt<ShellNavigationService>(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _widgetLaunchHandler.start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetLaunchHandler.dispose();
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
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: theme,
        themeAnimationDuration: AppThemeAnimation.duration,
        themeAnimationCurve: AppThemeAnimation.curve,
        builder: (context, child) => JoinLinkBinder(
          child: FloatingOverlayBinder(
            child: HomeWidgetRefreshBinder(
              child: ThemeWaterDropHost(child: child ?? const SizedBox.shrink()),
            ),
          ),
        ),
        home: const Shell(),
      );
    });
  }
}
