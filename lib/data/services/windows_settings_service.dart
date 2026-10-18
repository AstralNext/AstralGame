import 'dart:io';

import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:signals/signals_core.dart';
import 'package:win32_registry/win32_registry.dart';

/// Windows 专属系统设置：开机启动（HKLM Run）与 UAC（EnableLUA）。
///
/// 应用 manifest 已是 `requireAdministrator`，写 HKLM 不需要额外提权，
/// 也不会再弹一次 UAC 确认。
class WindowsSettingsService {
  static const String _runKeyPath =
      r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _policiesKeyPath =
      r'Software\Microsoft\Windows\CurrentVersion\Policies\System';
  static const String _runValueName = 'AstralGame';
  static const String _enableLuaValueName = 'EnableLUA';

  /// 开机启动项是否指向当前可执行文件；非 Windows / 读取失败为 `null`。
  final autoStart = signal<bool?>(null);

  /// UAC 是否开启（`EnableLUA != 0`）；非 Windows / 读取失败为 `null`。
  final uacEnabled = signal<bool?>(null);

  /// 正在写入注册表。
  final busy = signal<bool>(false);

  bool get _supported => RuntimePlatform.isWindows;

  /// 开机启动命令：带 `--autostart`，只在开机拉起时生效「启动后到托盘」。
  String get _launchCommand => '"${Platform.resolvedExecutable}" --autostart';

  /// 从注册表同步真实状态。
  Future<void> refresh() async {
    if (!_supported) {
      autoStart.value = null;
      uacEnabled.value = null;
      return;
    }
    final results = await Future.wait([_readAutoStart(), _readUacEnabled()]);
    autoStart.value = results[0];
    uacEnabled.value = results[1];
  }

  Future<bool?> _readAutoStart() async {
    RegistryKey? key;
    try {
      key = Registry.openPath(RegistryHive.localMachine, path: _runKeyPath);
      final command = key.getStringValue(_runValueName);
      if (command == null || command.trim().isEmpty) return false;
      return _matchesCurrentExecutable(command);
    } catch (e) {
      appLogger.w('[WindowsSettingsService] 读取开机启动失败', error: e);
      return null;
    } finally {
      key?.close();
    }
  }

  Future<bool?> _readUacEnabled() async {
    RegistryKey? key;
    try {
      key = Registry.openPath(
        RegistryHive.localMachine,
        path: _policiesKeyPath,
      );
      final value = key.getIntValue(_enableLuaValueName);
      // 缺失时系统默认开启。
      return value == null ? true : value != 0;
    } catch (e) {
      appLogger.w('[WindowsSettingsService] 读取 UAC 状态失败', error: e);
      return null;
    } finally {
      key?.close();
    }
  }

  /// 写入 / 删除 HKLM Run 启动项；成功返回 true。
  Future<bool> setAutoStart(bool enabled) async {
    if (!_supported || busy.value) return false;
    busy.value = true;
    RegistryKey? key;
    try {
      key = Registry.openPath(
        RegistryHive.localMachine,
        path: _runKeyPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      if (enabled) {
        key.createValue(StringValue(_runValueName, _launchCommand));
      } else {
        try {
          key.deleteValue(_runValueName);
        } catch (_) {
          // 值本来就不存在，视为已关闭。
        }
      }
      return true;
    } catch (e) {
      appLogger.w('[WindowsSettingsService] 设置开机启动失败', error: e);
      return false;
    } finally {
      key?.close();
      busy.value = false;
      await refresh();
    }
  }

  /// 写入 `EnableLUA`（0 关闭 / 1 开启）；重启后生效。
  Future<bool> setUacEnabled(bool enabled) async {
    if (!_supported || busy.value) return false;
    busy.value = true;
    RegistryKey? key;
    try {
      key = Registry.openPath(
        RegistryHive.localMachine,
        path: _policiesKeyPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      key.createValue(Int32Value(_enableLuaValueName, enabled ? 1 : 0));
      return true;
    } catch (e) {
      appLogger.w('[WindowsSettingsService] 修改 UAC 设置失败', error: e);
      return false;
    } finally {
      key?.close();
      busy.value = false;
      await refresh();
    }
  }

  /// 启动项是否指向当前 exe（忽略引号与 `--autostart` 参数）。
  bool _matchesCurrentExecutable(String raw) {
    final trimmed = raw.trim();
    String path;
    if (trimmed.startsWith('"')) {
      final end = trimmed.indexOf('"', 1);
      path = end > 0 ? trimmed.substring(1, end) : trimmed;
    } else {
      path = trimmed.split(' ').first;
    }
    return path.toLowerCase() == Platform.resolvedExecutable.toLowerCase();
  }
}
