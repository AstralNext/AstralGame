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

  /// Android：显示在线用户悬浮窗（头像 / IP / 延迟）。
  final floatingOverlayEnabled = signal(false);

  /// 房间成员列表：简洁模式（仅显示 IP / 延迟）。
  final memberListCompact = signal(false);

  /// 网络：DHCP 自动分配虚拟 IP（关后可手动设置）。
  final isDhcp = signal(true);

  /// 网络：DHCPv6 自动分配虚拟 IPv6（EasyTier `dhcpv6`；关后不分配虚拟 IPv6）。
  final isDhcpv6 = signal(true);

  /// 网络：手动填写的固定虚拟 IP（仅 isDhcp=false 时生效）。默认留空，由用户填写后记忆。
  final virtualIp = signal('');

  /// 网络：手动填写的固定虚拟 IPv6（仅 isDhcpv6=false 时生效）。默认留空，由用户填写后记忆。
  final virtualIpv6 = signal('');

  /// Windows：开机启动后直接驻留托盘。
  final startToTray = signal(false);

  /// 启动后自动进入收藏的房间（全平台）。
  final autoEnterRoom = signal(false);

  /// 启动后自动进入的收藏房间 id（全平台）。
  final autoEnterBookmarkId = signal<int?>(null);

  void loadFromPersistence() {
    closeMinimize.value = _settings.getCloseMinimize();
    appThemeId.value = AppThemeIdCodec.fromIndex(_settings.getAppThemeIndex());
    disableP2p.value = _settings.isDisableP2p();
    floatingOverlayEnabled.value = _settings.isFloatingOverlayEnabled();
    memberListCompact.value = _settings.isMemberListCompact();
    isDhcp.value = _settings.getIsDhcp();
    isDhcpv6.value = _settings.getIsDhcpv6();
    virtualIp.value = _settings.getVirtualIp();
    virtualIpv6.value = _settings.getVirtualIpv6();
    startToTray.value = _settings.getStartToTray();
    autoEnterRoom.value = _settings.getAutoEnterRoom();
    autoEnterBookmarkId.value = _settings.getAutoEnterBookmarkId();
    if (RuntimePlatform.isAndroid) {
      syncHomeWidgetTheme(appThemeId.value);
    }
  }

  Future<void> saveToPersistence() async {
    await Future.wait([
      _settings.setCloseMinimize(closeMinimize.value),
      _settings.setAppThemeIndex(appThemeId.value.storageIndex),
      _settings.setDisableP2p(disableP2p.value),
      _settings.setFloatingOverlayEnabled(floatingOverlayEnabled.value),
      _settings.setMemberListCompact(memberListCompact.value),
      _settings.setIsDhcp(isDhcp.value),
      _settings.setIsDhcpv6(isDhcpv6.value),
      _settings.setVirtualIp(virtualIp.value),
      _settings.setVirtualIpv6(virtualIpv6.value),
      _settings.setStartToTray(startToTray.value),
      _settings.setAutoEnterRoom(autoEnterRoom.value),
      _settings.setAutoEnterBookmarkId(autoEnterBookmarkId.value),
    ]);
    if (RuntimePlatform.isAndroid) {
      await syncHomeWidgetTheme(appThemeId.value);
    }
  }
}
