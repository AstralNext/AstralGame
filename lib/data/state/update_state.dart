import 'dart:async';

import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:signals/signals.dart';

/// 更新相关状态
class UpdateState {
  UpdateState(this._settings);

  final AppSettingsService _settings;

  /// 是否加入测试版频道
  final beta = signal(false);

  /// 是否自动检查更新
  final autoCheckUpdate = signal(true);

  /// 最近一次检查到的最新版本号
  final latestVersion = signal<String?>(null);

  /// 是否正在检查更新
  final isChecking = signal(false);

  /// 从本地配置恢复开关（[AppSettingsService] 支持同步读取）。
  void loadFromPersistence() {
    beta.value = _settings.getUpdateBetaChannel();
    autoCheckUpdate.value = _settings.getUpdateAutoCheck();
  }

  void setBeta(bool value) {
    beta.value = value;
    unawaited(_settings.setUpdateBetaChannel(value));
  }

  void setAutoCheckUpdate(bool value) {
    autoCheckUpdate.value = value;
    unawaited(_settings.setUpdateAutoCheck(value));
  }

  void setLatestVersion(String? version) {
    latestVersion.value = version;
  }

  void toggleBeta() => setBeta(!beta.value);

  void toggleAutoCheckUpdate() => setAutoCheckUpdate(!autoCheckUpdate.value);

  /// 仅表示已经拿到可用版本号，不代表一定高于当前版本
  late final hasNewVersion = computed(() {
    final version = latestVersion.value;
    return version != null && version.trim().isNotEmpty;
  });
}
