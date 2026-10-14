import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/services/home_widget_sync_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/utils/join_protocol.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:astral_game/utils/single_instance_guard.dart';
import 'package:home_widget/home_widget.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 初始化完成后再 runApp：`waitUntilReadyToShow` 要等首帧才 show 窗口，
  // 因此不会出现中间的空窗口或加载页——双击后直接进主界面。
  // 启动耗时已在 setupDI 内做了并发化，尽量压短这段等待。
  await setupDI();
  await registerJoinProtocol();

  final nodeManager = getIt<NodeManagementService>();
  nodeManager.initUserInfo();

  if (RuntimePlatform.isAndroid) {
    refreshAndroidHomeWidgets();
  }

  runApp(const AstralGameApp());
}
