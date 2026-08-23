import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:astral_game/data/services/home_widget_sync_service.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/firebase_options.dart';
import 'package:astral_game/utils/join_protocol.dart';
import 'package:astral_game/utils/single_instance_guard.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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

  unawaited(_initFirebase());

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

bool get _crashlyticsSupported =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

bool get _analyticsSupported =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

Future<void> _initFirebase() async {
  if (!_analyticsSupported && !_crashlyticsSupported) return;
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (_analyticsSupported) {
    final analytics = FirebaseAnalytics.instance;
    await analytics.setAnalyticsCollectionEnabled(true);
    await analytics.logAppOpen();
  }

  if (!_crashlyticsSupported) return;
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}
