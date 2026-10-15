import 'package:astral_game/data/services/linux_capability_service.dart';
import 'package:astral_game/ui/widgets/app_snack_bar.dart';
import 'package:flutter/material.dart';

/// 提示缺少 CAP_NET_ADMIN 并引导授权（Linux 桌面）。
///
/// 返回 true 表示授权已完成（需用户自己重启应用才生效，不替他重启：
/// 重启失败时玩家只会看到「应用凭空消失」，反而更难解释）。
/// 返回 false 表示未完成授权（取消 / 授权失败）。
/// [startup] 为 true 时用于启动检测的措辞。
Future<bool> showLinuxCapabilityPrompt(
  BuildContext context, {
  required LinuxCapabilityService capability,
  bool startup = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('需要网络权限'),
      content: Text(
        startup
            ? 'Linux 上创建虚拟网卡需要 CAP_NET_ADMIN 权限，'
                  '当前进程没有该权限，加入房间后会一直拿不到虚拟 IP。\n\n'
                  '点击「立即授权」会弹出系统密码框：把 cap_net_admin / cap_net_raw '
                  '赋给本程序（必要时把随包动态库目录写入 '
                  '/etc/ld.so.conf.d/astral-game.conf），完成后请重启应用。'
            : 'Linux 上创建虚拟网卡需要 CAP_NET_ADMIN 权限。'
                  '点击「立即授权」会弹出系统密码框：把 cap_net_admin / cap_net_raw '
                  '赋给本程序（必要时把随包动态库目录写入 '
                  '/etc/ld.so.conf.d/astral-game.conf），完成后请重启应用。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('以后再说'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('立即授权'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  final result = await capability.grant();
  if (!context.mounted) return result == LinuxCapabilityGrant.granted;

  switch (result) {
    case LinuxCapabilityGrant.granted:
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('授权完成'),
          content: const Text('权限已写入，请重启 Astral Game 后生效。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return true;
    case LinuxCapabilityGrant.cancelled:
      showAppSnackBar(context, '已取消授权');
    case LinuxCapabilityGrant.notAuthorized:
      showAppSnackBar(context, '授权被拒绝：需要管理员账号（polkit）');
    case LinuxCapabilityGrant.setcapMissing:
      showAppSnackBar(context, '系统缺少 setcap 命令，请先安装 libcap');
    case LinuxCapabilityGrant.failed:
      showAppSnackBar(context, '授权失败，详见日志');
  }
  return false;
}
