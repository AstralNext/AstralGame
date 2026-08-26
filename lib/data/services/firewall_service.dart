import 'package:astral_game/utils/logger.dart';
import 'dart:io';

import 'package:astral_game/utils/runtime_platform.dart';
import 'package:astral_rust_core/astral_rust_core.dart' as ffi;
import 'package:signals/signals_core.dart';

/// 防火墙服务
///
/// 负责管理 Windows 防火墙状态
/// 仅在 Windows 平台有效
class FirewallService {
/// 专用配置文件是否启用；非 Windows 恒为 `null`。
final privateProfileEnabled = signal<bool?>(null);
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
return getFirewallStatus(profileIndex: 2);
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
await setFirewallStatus(2, enable);
privateProfileEnabled.value = enable;
await refreshPrivateProfile();
}
}
