import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/home_widget_sync_service.dart';
import 'package:astral_game/data/services/join_link_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/utils/join_protocol.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:astral_game/utils/single_instance_guard.dart';
import 'package:home_widget/home_widget.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 由开机启动项写入的标记，只有这种方式拉起时才考虑「启动后到托盘」。
  final launchedAtBoot = args.contains('--autostart');

  if (!await SingleInstanceGuard.tryAcquire()) {
    exit(0);
  }

  if (RuntimePlatform.isAndroid) {
    HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);
  }

  // Initialize window_manager only on desktop platforms
  if (RuntimePlatform.isDesktop) {
    await windowManager.ensureInitialized();

    const WindowOptions windowOptions = WindowOptions(
      size: Size(940, 560),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions);
  }

  // 初始化完成后再 runApp：窗口在首帧渲染后才显示，不会出现空窗口或加载页。
  // 启动耗时已在 setupDI 内做了并发化，尽量压短这段等待。
  // runApp 之前的任何一步抛异常，用户都只能看到 LaunchTheme 的黑屏，
  // 因此统一兜底成可见的错误页，便于定位（含缺少 Rust 动态库等情况）。
  try {
    await setupDI();
    await registerJoinProtocol();

    // 冷启动兜底：Linux 的 app_links 插件在窗口创建时才注册，拿不到首个
    // command-line；Windows/macOS 的链接也可能以参数形式传入。先解析一遍。
    getIt<JoinLinkService>().considerLaunchArguments(args);

    getIt<NodeManagementService>().initUserInfo();

    if (RuntimePlatform.isAndroid) {
      refreshAndroidHomeWidgets();
    }
  } catch (error, stackTrace) {
    debugPrint('启动初始化失败: $error\n$stackTrace');
    runApp(_StartupErrorApp(error: error));
    return;
  }

  // 是否开机静默驻留托盘，必须在 setupDI 之后判断：prefs 此时才加载完成。
  // 原生侧在 --autostart 时不再自动显示窗口，显示与否完全由这里决定。
  final startToTray =
      launchedAtBoot && getIt<AppSettingsService>().getStartToTray();

  runApp(const AstralGameApp());

  if (RuntimePlatform.isDesktop && !startToTray) {
    // 等首帧渲染完再显示，避免出现空白窗口。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showMainWindow());
    });
  }
}

Future<void> _showMainWindow() async {
  await windowManager.show();
  await windowManager.focus();
}

/// 启动初始化失败时的兜底页：只依赖 Flutter 自身，不依赖任何服务。
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF101014),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.white70,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '应用初始化失败',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
