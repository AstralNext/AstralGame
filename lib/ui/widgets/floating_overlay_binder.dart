import 'dart:async';

import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/floating_overlay_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 监听在线用户与悬浮窗开关，防抖后同步到 Android 原生悬浮层。
class FloatingOverlayBinder extends StatefulWidget {
  const FloatingOverlayBinder({super.key, required this.child});

  final Widget child;

  @override
  State<FloatingOverlayBinder> createState() => _FloatingOverlayBinderState();
}

class _FloatingOverlayBinderState extends State<FloatingOverlayBinder>
    with WidgetsBindingObserver {
  Timer? _debounce;
  EffectCleanup? _effectCleanup;
  final FloatingOverlayService _overlay = FloatingOverlayService();

  @override
  void initState() {
    super.initState();
    if (!RuntimePlatform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    final settings = getIt<SettingsState>();
    final nodes = getIt<NodeManagementService>();

    _effectCleanup = effect(() {
      settings.floatingOverlayEnabled.value;
      nodes.isRunning;
      nodes.userNodes.value.length;
      _scheduleSync();
    });
    _scheduleSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleSync();
    }
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _overlay.applyFromAppState(
        settings: getIt<AppSettingsService>(),
        nodes: getIt<NodeManagementService>(),
      );
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _effectCleanup?.call();
    if (RuntimePlatform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
