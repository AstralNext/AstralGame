import 'package:signals/signals.dart';

/// 子页面 / 小部件请求 Shell 切换底栏/侧栏 Tab。
class ShellNavigationService {
  /// `0` 联机，`1` 服务器，`2` 收藏，`3` 设置。
  final pendingTabIndex = signal<int?>(null);

  void openDashboardTab() => pendingTabIndex.value = 0;

  void openServersTab() => pendingTabIndex.value = 1;

  void openBookmarksTab() => pendingTabIndex.value = 2;

  void openSettingsTab() => pendingTabIndex.value = 3;

  void clearPending() => pendingTabIndex.value = null;
}
