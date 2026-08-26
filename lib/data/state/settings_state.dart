import 'package:astral_game/config/app_theme_id.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/home_widget_theme_sync.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:signals/signals.dart';

class SettingsState {
  SettingsState(this._settings);

  final AppSettingsService _settings;

  final closeMinimize = signal(true);
  final appThemeId = signal(AppThemeId.insCream);
  final disableP2p = signal(false);

  /// Windows：局域网 UDP 广播转发到虚拟网（EasyTier `enable_udp_broadcast_relay`）。
  final enableUdpBroadcastRelay = signal(false);

  /// Android：显示在线用户悬浮窗（头像 / IP / 延迟）。
  final floatingOverlayEnabled = signal(false);

  void loadFromPersistence() {
    closeMinimize.value = _settings.getCloseMinimize();
    final storedIndex = _settings.getAppThemeIndex();
    final AppThemeId resolved;
    if (_settings.getAppThemeSchema() < AppSettingsService.appThemeSchemaCurrent) {
      resolved = AppThemeIdCodec.fromLegacyIndex(storedIndex);
      _settings.setAppThemeSchema(AppSettingsService.appThemeSchemaCurrent);
      _settings.setAppThemeIndex(resolved.storageIndex);
    } else {
      resolved = AppThemeIdCodec.fromIndex(storedIndex);
    }
    appThemeId.value = resolved;
    disableP2p.value = _settings.isDisableP2p();
    enableUdpBroadcastRelay.value = _settings.isEnableUdpBroadcastRelay();
    floatingOverlayEnabled.value = _settings.isFloatingOverlayEnabled();
    if (RuntimePlatform.isAndroid) {
      syncHomeWidgetTheme(appThemeId.value);
    }
  }

  Future<void> saveToPersistence() async {
    await Future.wait([
      _settings.setCloseMinimize(closeMinimize.value),
      _settings.setAppThemeIndex(appThemeId.value.storageIndex),
      _settings.setAppThemeSchema(AppSettingsService.appThemeSchemaCurrent),
      _settings.setDisableP2p(disableP2p.value),
      _settings.setEnableUdpBroadcastRelay(enableUdpBroadcastRelay.value),
      _settings.setFloatingOverlayEnabled(floatingOverlayEnabled.value),
    ]);
    if (RuntimePlatform.isAndroid) {
      await syncHomeWidgetTheme(appThemeId.value);
    }
  }
}
