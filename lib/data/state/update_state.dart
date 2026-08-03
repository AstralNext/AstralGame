import 'package:signals/signals.dart';

/// 更新相关状态
class UpdateState {
  /// 是否加入测试版频道
  final beta = signal(false);

  /// 是否自动检查更新
  final autoCheckUpdate = signal(true);

  /// 最近一次检查到的最新版本号
  final latestVersion = signal<String?>(null);

  /// 是否正在检查更新
  final isChecking = signal(false);

  void setBeta(bool value) {
    beta.value = value;
  }

  void setAutoCheckUpdate(bool value) {
    autoCheckUpdate.value = value;
  }

  void setLatestVersion(String? version) {
    latestVersion.value = version;
  }

  void toggleBeta() {
    beta.value = !beta.value;
  }

  void toggleAutoCheckUpdate() {
    autoCheckUpdate.value = !autoCheckUpdate.value;
  }

  /// 仅表示已经拿到可用版本号，不代表一定高于当前版本
  late final hasNewVersion = computed(() {
    final version = latestVersion.value;
    return version != null && version.trim().isNotEmpty;
  });
}
