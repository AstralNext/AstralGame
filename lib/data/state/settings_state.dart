import 'dart:async';

import 'package:astral_game/config/app_theme_id.dart';
import 'package:astral_game/data/models/transport_mode.dart';
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

  /// 联机模式：EasyTier 组网 / Steam 组网（SDR 虚拟局域网，Windows 实验性）。
  final transportMode = signal(TransportMode.easytier);

  /// 实验性功能开关：目前只控制 Steam 组网，仅 Windows 提供入口，默认关闭。
  final experimentalSteam = signal(false);

  /// 启动时历史配置因平台/开关不可用而被回落的一次性提示。
  final transportFallbackNotice = signal<String?>(null);

  /// 本次是否由「双机自检」脚本拉起（`--steam-selftest`）：只影响本次运行，
  /// 不写回存储，用来直接露出 Steam Tab 和自检入口。
  final steamSelfTestLaunch = signal(false);

  /// 自检客人脚本里粘贴的大厅 id；空表示走搜房。
  String? steamSelfTestLobbyId;

  /// 解析自检脚本的启动参数。
  ///
  /// 必须在 [loadFromPersistence] 之后调用：这里只改内存，覆盖平台/存储的回落，
  /// 退出程序后仍是用户原来的配置。
  void applySelfTestLaunch(List<String> args) {
    if (!args.contains('--steam-selftest')) return;
    if (!RuntimePlatform.isWindows) return;
    for (final arg in args) {
      if (arg.startsWith('--selftest-lobby=')) {
        final id = arg.substring('--selftest-lobby='.length).trim();
        steamSelfTestLobbyId = id.isEmpty ? null : id;
      }
    }
    steamSelfTestLaunch.value = true;
    experimentalSteam.value = true;
    transportMode.value = TransportMode.steam;
    transportFallbackNotice.value = null;
  }

  /// 传输模式可用性的统一判定入口（平台 + 实验性开关）。
  TransportGate get transportGate =>
      TransportGate.current(experimentalSteamEnabled: experimentalSteam.value);

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
    // 非 Windows 没有开关入口，按关闭处理，避免历史值把 Steam 放出来。
    experimentalSteam.value =
        RuntimePlatform.isWindows && _settings.getExperimentalSteamEnabled();
    final storedMode = _settings.getTransportMode();
    final gatedMode = transportGate.fallback(storedMode);
    transportMode.value = gatedMode;
    if (gatedMode != storedMode) {
      // 历史配置在当前环境不可用：回落 EasyTier、写回存储并说明一次原因。
      unawaited(_settings.setTransportMode(gatedMode));
      transportFallbackNotice.value =
          '${transportGate.unavailableReason(storedMode) ?? '当前环境不支持所选联机模式'}，已回落为 EasyTier 组网';
    }
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
      _settings.setTransportMode(transportMode.value),
      _settings.setExperimentalSteamEnabled(experimentalSteam.value),
      _settings.setStartToTray(startToTray.value),
      _settings.setAutoEnterRoom(autoEnterRoom.value),
      _settings.setAutoEnterBookmarkId(autoEnterBookmarkId.value),
    ]);
    if (RuntimePlatform.isAndroid) {
      await syncHomeWidgetTheme(appThemeId.value);
    }
  }
}
