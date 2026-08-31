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

  /// 网络：DHCP 自动分配虚拟 IP（关后可手动设置）。
  final isDhcp = signal(true);

  /// 网络：手动填写的固定虚拟 IP（仅 isDhcp=false 时生效）。
  final virtualIp = signal('10.147.0.0');

  void loadFromPersistence() {
    closeMinimize.value = _settings.getCloseMinimize();
    appThemeId.value = AppThemeIdCodec.fromIndex(_settings.getAppThemeIndex());
    disableP2p.value = _settings.isDisableP2p();
    enableUdpBroadcastRelay.value = _settings.isEnableUdpBroadcastRelay();
    floatingOverlayEnabled.value = _settings.isFloatingOverlayEnabled();
    isDhcp.value = _settings.getIsDhcp();
    virtualIp.value = _settings.getVirtualIp();
    if (RuntimePlatform.isAndroid) {
      syncHomeWidgetTheme(appThemeId.value);
    }
  }

  Future<void> saveToPersistence() async {
    await Future.wait([
      _settings.setCloseMinimize(closeMinimize.value),
      _settings.setAppThemeIndex(appThemeId.value.storageIndex),
      _settings.setDisableP2p(disableP2p.value),
      _settings.setEnableUdpBroadcastRelay(enableUdpBroadcastRelay.value),
      _settings.setFloatingOverlayEnabled(floatingOverlayEnabled.value),
      _settings.setIsDhcp(isDhcp.value),
      _settings.setVirtualIp(virtualIp.value),
    ]);
    if (RuntimePlatform.isAndroid) {
      await syncHomeWidgetTheme(appThemeId.value);
    }
  }
}
