import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/services/home_widget_launch_handler.dart';
import 'package:astral_game/data/services/linux_capability_service.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/shell/shell.dart';
import 'package:astral_game/ui/widgets/floating_overlay_binder.dart';
import 'package:astral_game/ui/widgets/home_widget_refresh_binder.dart';
import 'package:astral_game/ui/widgets/join_link_binder.dart';
import 'package:astral_game/ui/widgets/linux_capability_prompt.dart';
import 'package:astral_game/ui/widgets/theme_water_drop_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:signals/signals_flutter.dart';

class AstralGameApp extends StatefulWidget {
  const AstralGameApp({super.key});

  @override
  State<AstralGameApp> createState() => _AstralGameAppState();
}

class _AstralGameAppState extends State<AstralGameApp>
    with WidgetsBindingObserver {
  bool _disposed = false;
  final _widgetLaunchHandler = HomeWidgetLaunchHandler(
    navigation: getIt<ShellNavigationService>(),
  );

  /// 启动提示需要挂在 [MaterialApp] 内部（否则拿不到 MaterialLocalizations）。
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _widgetLaunchHandler.start();
      _maybePromptLinuxCapability();
    });
  }

  /// Linux 桌面：缺少 CAP_NET_ADMIN 时提示授权，否则加入房间会一直拿不到虚拟 IP。
  ///
  /// 必须用 [MaterialApp] 内部的 context 弹窗；用本 State 的 context 会因为
  /// 拿不到 MaterialLocalizations 直接抛异常。
  Future<void> _maybePromptLinuxCapability() async {
    final capability = getIt<LinuxCapabilityService>();
    if (!capability.applies || capability.canCreateTun) return;
    if (capability.pendingRestart.value) return;
    if (!mounted) return;

    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) {
      // 首帧时 Navigator 还没挂上，等下一帧再试一次。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybePromptLinuxCapability();
      });
      return;
    }

    await showLinuxCapabilityPrompt(
      navigatorContext,
      capability: capability,
      startup: true,
    );
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
        navigatorKey: _navigatorKey,
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
        builder: (context, child) => FloatingOverlayBinder(
          child: HomeWidgetRefreshBinder(
            child: ThemeWaterDropHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
        // 必须挂在 Navigator 之下：进房流程会弹确认框/Toast，
        // 而 MaterialApp.builder 的 context 在 Overlay 之上，Overlay.of 会抛异常。
        home: const JoinLinkBinder(child: Shell()),
      );
    });
  }
}
