import 'dart:async';
import 'dart:io';

import 'package:astral_game/config/home_widget_uris.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:home_widget/home_widget.dart';

/// 处理从小部件启动 / 点击带来的 URI，切换 Tab。
///
/// 收藏（Rooms）路径：跳到 Dashboard 首页，用户在首页收藏预览卡/⭐入口
/// 进入「我的收藏」页查看详情，不再"自动选中某个收藏"（避免误操作触发连接）。
class HomeWidgetLaunchHandler {
  HomeWidgetLaunchHandler({
    required ShellNavigationService navigation,
  }) : _navigation = navigation;

  final ShellNavigationService _navigation;
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

    final path = uri.path;
    if (path == HomeWidgetUris.pathMembers ||
        path == HomeWidgetUris.pathConnect ||
        path == HomeWidgetUris.pathRooms) {
      _navigation.openDashboardTab();
    }
  }
}
