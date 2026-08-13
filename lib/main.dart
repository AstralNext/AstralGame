import 'dart:io';

import 'package:astral_game/data/services/home_widget_sync_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/firebase_options.dart';
import 'package:astral_game/utils/join_protocol.dart';
import 'package:astral_game/utils/single_instance_guard.dart';
import 'package:firebase_core/firebase_core.dart';
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

  await _initFirebase();

  if (Platform.isAndroid) {
    HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);
  }

  // Initialize window_manager only on desktop platforms
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = const WindowOptions(
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

  await setupDI();
  await registerJoinProtocol();

  final nodeManager = getIt<NodeManagementService>();
  nodeManager.initUserInfo();

  if (Platform.isAndroid) {
    refreshAndroidHomeWidgets();
  }

  runApp(const AstralGameApp());
}

Future<void> _initFirebase() async {
  if (Platform.isLinux) return;
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}
