import 'dart:async';
import 'dart:io';

import 'package:astral_game/config/home_widget_uris.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:home_widget/home_widget.dart';

/// 处理从小部件启动 / 点击带来的 URI，切换 Tab 或选中房间。
class HomeWidgetLaunchHandler {
  HomeWidgetLaunchHandler({
    required ShellNavigationService navigation,
    required RoomState roomState,
  })  : _navigation = navigation,
        _roomState = roomState;

  final ShellNavigationService _navigation;
  final RoomState _roomState;
  StreamSubscription<Uri?>? _sub;

  Future<void> start() async {
    if (!RuntimePlatform.isAndroid) return;
    final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
    _handle(initial);
    _sub = HomeWidget.widgetClicked.listen(_handle);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  void _handle(Uri? uri) {
    if (uri == null) return;
    if (uri.scheme != HomeWidgetUris.scheme || uri.host != HomeWidgetUris.host) {
      return;
    }

    final nav = _navigation;
    final path = uri.path;

    if (path == HomeWidgetUris.pathMembers ||
        path == HomeWidgetUris.pathConnect ||
        path == HomeWidgetUris.pathRooms) {
      nav.openDashboardTab();
    }

    if (path == HomeWidgetUris.pathRooms) {
      final idRaw = uri.queryParameters['id'];
      final code = uri.queryParameters['code'];
      final roomState = _roomState;
      if (idRaw != null) {
        final id = int.tryParse(idRaw);
        if (id != null) {
          roomState.selectRoomById(id);
          return;
        }
      }
      if (code != null && code.isNotEmpty) {
        roomState.selectRoomByCode(code);
      }
    }
  }
}
