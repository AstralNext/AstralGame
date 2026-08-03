import 'dart:io';

import 'package:astral_game/config/app_theme_id.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/home_widget_theme_sync.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals.dart';

class SettingsState {
  final closeMinimize = signal(true);
  final appThemeId = signal(AppThemeId.insCream);
  final disableP2p = signal(false);

  /// Windows：局域网 UDP 广播转发到虚拟网（EasyTier `enable_udp_broadcast_relay`）。
  final enableUdpBroadcastRelay = signal(false);

  /// Android：显示在线用户悬浮窗（头像 / IP / 延迟）。
  final floatingOverlayEnabled = signal(false);

  void loadFromPersistence() {
    final settings = GetIt.I<AppSettingsService>();
    closeMinimize.value = settings.getCloseMinimize();
    final storedIndex = settings.getAppThemeIndex();
    final AppThemeId resolved;
    if (settings.getAppThemeSchema() < AppSettingsService.appThemeSchemaCurrent) {
      resolved = AppThemeIdCodec.fromLegacyIndex(storedIndex);
      settings.setAppThemeSchema(AppSettingsService.appThemeSchemaCurrent);
      settings.setAppThemeIndex(resolved.storageIndex);
    } else {
      resolved = AppThemeIdCodec.fromIndex(storedIndex);
    }
    appThemeId.value = resolved;
    disableP2p.value = settings.isDisableP2p();
    enableUdpBroadcastRelay.value = settings.isEnableUdpBroadcastRelay();
    floatingOverlayEnabled.value = settings.isFloatingOverlayEnabled();
    if (Platform.isAndroid) {
      syncHomeWidgetTheme(appThemeId.value);
    }
  }

  Future<void> saveToPersistence() async {
    final settings = GetIt.I<AppSettingsService>();
    await Future.wait([
      settings.setCloseMinimize(closeMinimize.value),
      settings.setAppThemeIndex(appThemeId.value.storageIndex),
      settings.setAppThemeSchema(AppSettingsService.appThemeSchemaCurrent),
      settings.setDisableP2p(disableP2p.value),
      settings.setEnableUdpBroadcastRelay(enableUdpBroadcastRelay.value),
      settings.setFloatingOverlayEnabled(floatingOverlayEnabled.value),
    ]);
    if (Platform.isAndroid) {
      await syncHomeWidgetTheme(appThemeId.value);
    }
  }
}
