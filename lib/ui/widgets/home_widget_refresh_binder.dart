import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/services/home_widget_sync_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

/// 监听房间/连接/成员/主题变化，防抖后刷新 Android 桌面小部件。
class HomeWidgetRefreshBinder extends StatefulWidget {
  const HomeWidgetRefreshBinder({super.key, required this.child});

  final Widget child;

  @override
  State<HomeWidgetRefreshBinder> createState() => _HomeWidgetRefreshBinderState();
}

class _HomeWidgetRefreshBinderState extends State<HomeWidgetRefreshBinder>
    with WidgetsBindingObserver {
  Timer? _debounce;
  EffectCleanup? _effectCleanup;

  @override
  void initState() {
    super.initState();
    if (!RuntimePlatform.isAndroid) return;
    WidgetsBinding.instance.addObserver(this);
    final roomState = getIt<RoomState>();
    final settings = getIt<SettingsState>();
    final nodes = getIt<NodeManagementService>();

    _effectCleanup = effect(() {
      roomState.connectedRoomName.value;
      nodes.isRunning;
      roomState.bookmarksList.value.length;
      settings.appThemeId.value;
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
    _debounce = Timer(const Duration(milliseconds: 400), () {
      refreshAndroidHomeWidgets();
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
