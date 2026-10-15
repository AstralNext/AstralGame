import 'dart:io';

import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals.dart';

/// pkexec 授权结果。
enum LinuxCapabilityGrant {
  /// 授权成功（setcap 已写入，下次启动进程才带上能力）。
  granted,

  /// 用户取消了 polkit 授权弹窗。
  cancelled,

  /// polkit 拒绝授权（非管理员账号 / 策略不允许）。
  notAuthorized,

  /// 系统里找不到 setcap（缺 libcap 工具）。
  setcapMissing,

  /// 其它失败，详情见日志。
  failed,
}

/// Linux 桌面：创建 / 配置 tun 虚拟网卡要求进程具备 `CAP_NET_ADMIN`
/// （Linux 上由 EasyTier 在自身进程内建 tun，只有 Android 走 VpnService 传 fd）。
///
/// 普通用户默认没有该能力，表现为「连接成功但一直拿不到虚拟 IP」。
/// 这里检测当前进程的 effective 能力位，并提供经 polkit（pkexec）给可执行文件
/// 打 `cap_net_admin,cap_net_raw+ep` 的一次性授权。
///
/// 两点必须知道：
/// - 能力在 exec 时生效，授权成功后需要**用户自己重启应用**才带上（不自作主张替他重启：
///   一旦重启失败，玩家的体验是「应用凭空消失」，且看不到任何报错）；
/// - 重新构建产物会覆盖可执行文件，能力随之丢失，需要重新授权。
class LinuxCapabilityService {
  LinuxCapabilityService();

  /// `/proc/self/status` 的 `CapEff` 里 CAP_NET_ADMIN 的位号。
  static const int _capNetAdminBit = 12;

  /// CAP_NET_RAW（原始套接字，ICMP echo / ping 用）的位号。
  static const int _capNetRawBit = 13;

  /// 本次进程内已完成授权、等重启生效。
  final pendingRestart = signal(false);

  /// 仅 Linux 桌面需要这套检查。
  bool get applies => RuntimePlatform.isLinux;

  /// 当前进程是否具备 CAP_NET_ADMIN。
  bool hasNetAdmin() => _hasEffectiveCapability(_capNetAdminBit);

  /// 当前进程是否具备 CAP_NET_RAW。
  bool hasNetRaw() => _hasEffectiveCapability(_capNetRawBit);

  /// 当前进程是否已经能建虚拟网卡（「已授权待重启」不算，需实际具备）。
  bool get canCreateTun => !applies || hasNetAdmin();

  /// 当前运行的可执行文件（`flutter run` 下是 bundle 里的产物）。
  String get executablePath => Platform.resolvedExecutable;

  bool _hasEffectiveCapability(int bit) {
    if (!applies) return true;
    try {
      final status = File('/proc/self/status').readAsStringSync();
      final match = RegExp(
        r'^CapEff:\s*([0-9a-fA-F]+)',
        multiLine: true,
      ).firstMatch(status);
      if (match == null) return false;
      final caps = int.parse(match.group(1)!, radix: 16);
      return caps & (1 << bit) != 0;
    } catch (e) {
      // 读不到能力位（非 Linux 布局 / 无 /proc）时按「有」处理，避免误报。
      appLogger.w('[LinuxCapability] 读取 /proc/self/status 失败: $e');
      return true;
    }
  }

  /// 授权脚本，在 pkexec 的 root 环境里执行。参数走位置参数，避免转义问题：
  /// `$1` 主程序、`$2` bundle/lib、`$3` ldconfig、`$4` ld.so.conf 路径、`$5` setcap
  /// （ldconfig / setcap 传绝对路径，不用 PATH——pkexec 环境里的 PATH 不可控）。
  ///
  /// 为什么必须先确认动态库能找到：给主程序打上 file capabilities 后，进程会被
  /// 内核标记为 secure-execution，glibc 在该模式下**只认 `ld.so.cache`（和 DT_RPATH）**，
  /// 会忽略 `DT_RUNPATH`（bundle 里正是 `$ORIGIN/lib`）与 `LD_LIBRARY_PATH`，
  /// 于是主程序连自己的插件 `.so` 都加载不到、启动即挂。
  /// 注意不能用 `ldd` 来判断：实测 `ldd` 跑在带 caps 的二进制上依然报告「都找得到」，
  /// 会把真实失败盖掉；而 `ldconfig -p` 直接反映缓存内容，正是该模式下唯一生效的来源。
  /// 所以：缓存没覆盖 bundle 的 lib 目录就把目录写进 `/etc/ld.so.conf.d/` 再 ldconfig，
  /// 仍然覆盖不到就 `setcap -r` 回滚——绝不能把主程序改成一个起不来的程序。
  static const String _grantScript = r'''
"$5" cap_net_admin,cap_net_raw+ep "$1" || exit 4
out=$("$3" -p 2>/dev/null)
case "$out" in
  *"$2/"*) exit 0 ;;
esac
printf '%s\n' "$2" > "$4" || { "$5" -r "$1"; exit 5; }
"$3" || { "$5" -r "$1"; exit 5; }
out=$("$3" -p 2>/dev/null)
case "$out" in
  *"$2/"*) exit 0 ;;
  *) "$5" -r "$1"; exit 6 ;;
esac
''';

  /// bundle 里动态库目录对应的 ld.so.conf.d 配置（仅在 secure 模式挡路时写入）。
  static const String _ldSoConfPath = '/etc/ld.so.conf.d/astral-game.conf';

  /// 经 pkexec 给 [executablePath] 打 setcap，并保证打完还能加载动态库；
  /// 成功后置 [pendingRestart]。
  Future<LinuxCapabilityGrant> grant() async {
    if (!applies) return LinuxCapabilityGrant.failed;

    final setcap = _resolveOnPath('setcap');
    if (setcap == null) {
      appLogger.w('[LinuxCapability] PATH 中找不到 setcap（libcap）');
      return LinuxCapabilityGrant.setcapMissing;
    }
    final sh = _resolveOnPath('sh') ?? '/bin/sh';
    final ldconfig = _resolveOnPath('ldconfig');
    if (_resolveOnPath('pkexec') == null) {
      appLogger.w('[LinuxCapability] PATH 中找不到 pkexec（polkit）');
      return LinuxCapabilityGrant.notAuthorized;
    }
    if (ldconfig == null) {
      appLogger.w('[LinuxCapability] 缺少 ldconfig，无法安全授予权限');
      return LinuxCapabilityGrant.failed;
    }

    try {
      final result = await Process.run('pkexec', [
        sh,
        '-c',
        _grantScript,
        'astral-grant',
        executablePath,
        p.join(p.dirname(executablePath), 'lib'),
        ldconfig,
        _ldSoConfPath,
        setcap,
      ]);
      final code = result.exitCode;
      appLogger.i('[LinuxCapability] pkexec 授权 exit=$code');
      if (code == 0) {
        pendingRestart.value = true;
        return LinuxCapabilityGrant.granted;
      }
      // pkexec：126 = 授权弹窗被取消 / 无法弹出；127 = 未授权。
      if (code == 126) return LinuxCapabilityGrant.cancelled;
      if (code == 127) return LinuxCapabilityGrant.notAuthorized;
      appLogger.w('[LinuxCapability] 授权失败 exit=$code: ${result.stderr}'.trim());
      return LinuxCapabilityGrant.failed;
    } catch (e) {
      appLogger.w('[LinuxCapability] 调用 pkexec 异常: $e');
      return LinuxCapabilityGrant.failed;
    }
  }

  /// 在 PATH 中查找可执行文件绝对路径（pkexec 要求绝对路径）。
  String? _resolveOnPath(String name) {
    final path = Platform.environment['PATH'];
    if (path == null || path.isEmpty) return null;
    for (final dir in path.split(':')) {
      if (dir.isEmpty) continue;
      final candidate = '$dir/$name';
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }
}
