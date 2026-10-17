import 'package:astral_game/utils/logger.dart';

import 'package:astral_game/utils/runtime_platform.dart';
import 'package:astral_game/src/rust/api/firewall.dart' as ffi;
import 'package:signals/signals_core.dart';

/// 防火墙服务
///
/// 负责管理 Windows 防火墙状态
/// 仅在 Windows 平台有效
class FirewallService {
  /// 域配置文件。
  static const int domainProfile = 1;

  /// 专用配置文件。
  static const int privateProfile = 2;

  /// 公用配置文件。
  static const int publicProfile = 3;

  static const List<int> _allProfiles = [
    domainProfile,
    privateProfile,
    publicProfile,
  ];

  /// 专用配置文件是否启用；非 Windows 恒为 `null`。
  final privateProfileEnabled = signal<bool?>(null);

  /// 三个配置文件是否全部关闭；非 Windows 或读取失败为 `null`。
  final allProfilesDisabled = signal<bool?>(null);

  /// 一键操作进行中。
  final busy = signal<bool>(false);

  /// 获取指定配置文件的防火墙状态
  ///
  /// [profileIndex] 配置文件索引: 1=域, 2=专用, 3=公用
  Future<bool> getFirewallStatus({int profileIndex = 2}) async {
    try {
      return await ffi.getFirewallStatus(profileIndex: profileIndex);
    } catch (e) {
      return false;
    }
  }

  /// 设置指定配置文件的防火墙状态
  ///
  /// [profileIndex] 配置文件索引: 1=域, 2=专用, 3=公用
  /// [enable] 是否启用防火墙
  Future<void> setFirewallStatus(int profileIndex, bool enable) async {
    try {
      await ffi.setFirewallStatus(profileIndex: profileIndex, enable: enable);
    } catch (e) {
      // 忽略错误
    }
  }

  /// 获取专用网络防火墙状态（最常用）
  Future<bool> getPrivateFirewallStatus() async {
    return getFirewallStatus();
  }

  /// 从系统读取并写入 [`privateProfileEnabled`]（供 RPC / 在线列表共享）。
  Future<void> refreshPrivateProfile() async {
    if (!RuntimePlatform.isWindows) {
      privateProfileEnabled.value = null;
      return;
    }
    try {
      privateProfileEnabled.value = await getPrivateFirewallStatus();
    } catch (e) {
      appLogger.w('[FirewallService] 操作失败', error: e);
      privateProfileEnabled.value = null;
    }
  }

  /// RPC 上报用：`enabled` / `disabled` / `unsupported`。
  String firewallWireValue() {
    if (!RuntimePlatform.isWindows) return 'unsupported';
    final enabled = privateProfileEnabled.value;
    if (enabled == null) return 'unsupported';
    return enabled ? 'enabled' : 'disabled';
  }

  /// 设置专用网络防火墙状态（最常用）
  Future<void> setPrivateFirewallStatus(bool enable) async {
    await setFirewallStatus(privateProfile, enable);
    privateProfileEnabled.value = enable;
    await refreshPrivateProfile();
  }

  /// 从系统读取三个配置文件状态：全部关闭才为 `true`。
  Future<void> refreshAllProfiles() async {
    if (!RuntimePlatform.isWindows) {
      allProfilesDisabled.value = null;
      return;
    }
    try {
      var anyEnabled = false;
      for (final index in _allProfiles) {
        if (await ffi.getFirewallStatus(profileIndex: index)) {
          anyEnabled = true;
          break;
        }
      }
      allProfilesDisabled.value = !anyEnabled;
    } catch (e) {
      appLogger.w('[FirewallService] 读取防火墙配置失败', error: e);
      allProfilesDisabled.value = null;
    }
  }

  /// 一键设置三个配置文件；任一步失败返回 `false`。
  Future<bool> setAllProfilesFirewallStatus(bool enable) async {
    if (!RuntimePlatform.isWindows || busy.value) return false;
    busy.value = true;
    var ok = true;
    try {
      for (final index in _allProfiles) {
        await ffi.setFirewallStatus(profileIndex: index, enable: enable);
      }
    } catch (e) {
      ok = false;
      appLogger.w('[FirewallService] 设置防火墙失败', error: e);
    }
    await refreshAllProfiles();
    await refreshPrivateProfile();
    busy.value = false;
    return ok;
  }
}
