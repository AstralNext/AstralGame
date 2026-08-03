import 'package:signals/signals.dart';

/// 子页面请求 Shell 切换底栏/侧栏 Tab（如「去服务器页」）。
class ShellNavigationService {
  /// `0` 主页，`1` 服务器，`2` 设置。
  final pendingTabIndex = signal<int?>(null);

  void openServersTab() => pendingTabIndex.value = 1;

  void clearPending() => pendingTabIndex.value = null;
}
