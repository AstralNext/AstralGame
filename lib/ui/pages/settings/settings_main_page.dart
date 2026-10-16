import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/data/state/update_state.dart';
import 'package:astral_game/data/state/theme_reveal_state.dart';
import 'package:astral_game/ui/widgets/app_snack_bar.dart';
import 'package:astral_game/ui/widgets/astral_grouped_tile.dart';
import 'package:astral_game/ui/widgets/astral_settings_section.dart';
import 'package:astral_game/ui/widgets/confirm_dialog.dart';
import 'package:astral_game/ui/widgets/fade_in_section.dart';
import 'package:astral_game/ui/widgets/linux_capability_prompt.dart';
import 'package:astral_game/ui/navigation/astral_page_route.dart';
import 'package:astral_game/ui/widgets/theme_picker_sheet.dart';
import 'package:astral_game/data/services/floating_overlay_service.dart';
import 'package:astral_game/data/services/linux_capability_service.dart';
import 'package:astral_game/data/services/network_optimize_service.dart';
import 'package:astral_game/utils/input_validator.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import 'about_page.dart';
import 'speed_test_page.dart';
import 'vpn_routes_page.dart';

/// 设置主页面。所有持久化字段统一通过 [SettingsState] signals 管理。
///
/// 行组件统一走 [AstralGroupedTile]（MD3：主色图标 + 缩进分隔线 + trailing 控件），
/// 分区标题统一在卡片上方（[buildSettingsHeader]）。
class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({super.key});

  @override
  State<SettingsMainPage> createState() => _SettingsMainPageState();
}

class _SettingsMainPageState extends State<SettingsMainPage> {
  static bool get _isDesktop {
    final os = RuntimePlatform.operatingSystem;
    return os != 'android' && os != 'ios';
  }

  static bool get _isAndroid => RuntimePlatform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final settingsState = getIt<SettingsState>();
    final updateState = getIt<UpdateState>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.pagePaddingH,
        AppDimensions.pagePaddingV,
        AppDimensions.pagePaddingH,
        24,
      ),
      children: [
        FadeInSection(
          child: Watch((context) {
            final id = settingsState.appThemeId.value;
            return AstralSettingsSection(
              title: '外观',
              items: [
                AstralSettingItem(
                  icon: Icons.palette_outlined,
                  label: '主题',
                  subtitle: id.label,
                  onTap: () async {
                    final picked = await showAppThemePickerSheet(
                      context,
                      current: id,
                    );
                    if (picked == null || picked.themeId == id) return;

                    await Future<void>.delayed(
                      const Duration(milliseconds: 60),
                    );
                    if (!context.mounted) return;

                    getIt<ThemeRevealController>().beginReveal(
                      origin: picked.origin,
                      newTheme: picked.themeId,
                    );
                    await settingsState.saveToPersistence();
                  },
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: AppDimensions.sectionGap),
        FadeInSection(
          order: 1,
          child: AstralSettingsFormCard(
            title: '应用',
            rows: [
              if (_isDesktop)
                _switchRow(
                  icon: Icons.window_outlined,
                  title: '关闭时最小化到托盘',
                  subtitle: () => '点击关闭时最小化到托盘区',
                  value: () => settingsState.closeMinimize.value,
                  onChanged: (v) {
                    settingsState.closeMinimize.value = v;
                    settingsState.saveToPersistence();
                  },
                ),
              _switchRow(
                icon: Icons.system_update_outlined,
                title: '自动检查更新',
                value: () => updateState.autoCheckUpdate.value,
                onChanged: updateState.setAutoCheckUpdate,
              ),
              _switchRow(
                icon: Icons.science_outlined,
                title: '使用测试版本',
                subtitle: () => '非专业用户不要开启此选项',
                value: () => updateState.beta.value,
                onChanged: updateState.setBeta,
              ),
              if (_isAndroid)
                _switchRow(
                  icon: Icons.picture_in_picture_alt_outlined,
                  title: '在线用户悬浮窗',
                  subtitle: () => '透明 HUD，不挡触摸；显示头像、IP、延迟列表',
                  value: () => settingsState.floatingOverlayEnabled.value,
                  onChanged: (v) =>
                      _onFloatingOverlayChanged(context, settingsState, v),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.sectionGap),
        FadeInSection(order: 2, child: _buildNetworkSection(settingsState)),
        const SizedBox(height: AppDimensions.sectionGap),
        FadeInSection(
          order: 3,
          child: AstralSettingsSection(
            title: '其他',
            items: [
              AstralSettingItem(
                icon: Icons.info_outline_rounded,
                label: '关于 Astral Game',
                onTap: () => Navigator.of(
                  context,
                ).push<void>(astralPageRoute(const AboutPage())),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 开关行的声明式包装：value/subtitle 用 getter 延迟取，行内自包 [Watch]，
  /// 整行可点切换，trailing 为 MD3 [Switch.adaptive]。
  static AstralSettingRow _switchRow({
    required IconData icon,
    required String title,
    String Function()? subtitle,
    required bool Function() value,
    required ValueChanged<bool>? onChanged,
  }) {
    return (index, count) => Watch((context) {
      final v = value();
      return AstralGroupedTile(
        icon: icon,
        label: title,
        subtitle: subtitle?.call(),
        index: index,
        count: count,
        onTap: onChanged == null ? null : () => onChanged(!v),
        trailing: Switch.adaptive(value: v, onChanged: onChanged),
      );
    });
  }

  Future<void> _onFloatingOverlayChanged(
    BuildContext context,
    SettingsState settingsState,
    bool enabled,
  ) async {
    settingsState.floatingOverlayEnabled.value = enabled;
    await settingsState.saveToPersistence();

    if (!enabled) {
      await FloatingOverlayService().hide();
      return;
    }

    final overlay = FloatingOverlayService();
    if (!await overlay.canDrawOverlays()) {
      if (!context.mounted) return;
      final goSettings = await showConfirmDialog(
        context,
        title: '需要悬浮窗权限',
        content:
            '请在系统设置中允许 Astral Game「显示在其他应用上层」，'
            '然后返回应用重新打开此开关。',
        confirmLabel: '去设置',
      );
      if (goSettings) {
        await overlay.openOverlayPermissionSettings();
      }
      settingsState.floatingOverlayEnabled.value = false;
      await settingsState.saveToPersistence();
      return;
    }

    await overlay.show();
  }

  Widget _buildNetworkSection(SettingsState settingsState) {
    return Watch((context) {
      final isDhcp = settingsState.isDhcp.value;
      final virtualIp = settingsState.virtualIp.value;
      final virtualIpv6 = settingsState.virtualIpv6.value;
      return AstralSettingsFormCard(
        title: '网络',
        rows: [
          _switchRow(
            icon: Icons.settings_ethernet_outlined,
            title: '自动分配虚拟IP',
            value: () => settingsState.isDhcp.value,
            onChanged: (value) {
              settingsState.isDhcp.value = value;
              settingsState.isDhcpv6.value = value;
              settingsState.saveToPersistence();
            },
          ),
          if (!isDhcp) ...[
            (index, count) => AstralGroupedTile(
              icon: Icons.lan_outlined,
              label: '虚拟IPv4地址',
              subtitle: virtualIp.isEmpty ? '未设置，点击填写' : virtualIp,
              index: index,
              count: count,
              onTap: () => _editVirtualIp(settingsState),
              trailing: FilledButton.tonal(
                onPressed: () => _editVirtualIp(settingsState),
                child: const Text('编辑'),
              ),
            ),
            (index, count) => AstralGroupedTile(
              icon: Icons.public_outlined,
              label: '虚拟IPv6地址',
              subtitle: virtualIpv6.isEmpty ? '未设置，点击填写' : virtualIpv6,
              index: index,
              count: count,
              onTap: () => _editVirtualIpv6(settingsState),
              trailing: FilledButton.tonal(
                onPressed: () => _editVirtualIpv6(settingsState),
                child: const Text('编辑'),
              ),
            ),
          ],
          (index, count) => AstralGroupedTile(
            icon: Icons.speed_outlined,
            label: '网络测速',
            subtitle: '全球网测节点：延迟 / 下行 / 上行',
            index: index,
            count: count,
            onTap: () => Navigator.of(
              context,
            ).push<void>(astralPageRoute(const SpeedTestPage())),
          ),
          _switchRow(
            icon: Icons.hub_outlined,
            title: '禁用 P2P',
            subtitle: () => '仅通过中继通信',
            value: () => settingsState.disableP2p.value,
            onChanged: (v) {
              settingsState.disableP2p.value = v;
              settingsState.saveToPersistence();
            },
          ),
          if (RuntimePlatform.operatingSystem == 'windows') ...[
            _switchRow(
              icon: Icons.settings_input_antenna,
              title: '强制 UDP 广播转发',
              subtitle: () => '在其他类游戏中开启，重新连接房间后生效',
              value: () => settingsState.enableUdpBroadcastRelay.value,
              onChanged: (v) {
                settingsState.enableUdpBroadcastRelay.value = v;
                settingsState.saveToPersistence();
              },
            ),
            (index, count) => Watch((context) {
              final optimize = getIt<NetworkOptimizeService>();
              final busy = optimize.busy.value;
              return AstralGroupedTile(
                icon: Icons.speed_outlined,
                label: '网络加速（仅限中国大陆）',
                subtitle: busy ? '正在安装或卸载…' : '自动选择最低延迟的IP',
                index: index,
                count: count,
                onTap: busy
                    ? null
                    : () => _onNetworkOptimizeChanged(
                        context,
                        optimize,
                        !optimize.installed.value,
                      ),
                trailing: Switch.adaptive(
                  value: optimize.installed.value,
                  onChanged: busy
                      ? null
                      : (v) => _onNetworkOptimizeChanged(context, optimize, v),
                ),
              );
            }),
          ],
          if (_isAndroid)
            (index, count) => AstralGroupedTile(
              icon: Icons.route_outlined,
              label: '自定义 VPN 路由',
              subtitle: '额外 CIDR；默认含虚拟网段、组播、广播',
              index: index,
              count: count,
              onTap: () => Navigator.of(
                context,
              ).push<void>(astralPageRoute(const VpnRoutesPage())),
            ),
          if (RuntimePlatform.isLinux)
            (index, count) => Watch((context) {
              final capability = getIt<LinuxCapabilityService>();
              final ready = capability.canCreateTun;
              final pending = capability.pendingRestart.value;
              return AstralGroupedTile(
                icon: Icons.shield_outlined,
                label: '虚拟网卡权限',
                subtitle: ready
                    ? '已具备 CAP_NET_ADMIN'
                    : pending
                    ? '已授权，重启应用后生效'
                    : '缺少 CAP_NET_ADMIN，加入房间会拿不到虚拟 IP',
                index: index,
                count: count,
                onTap: ready ? null : () => _onGrantLinuxCapability(context),
                trailing: ready
                    ? null
                    : FilledButton.tonal(
                        onPressed: () => _onGrantLinuxCapability(context),
                        child: const Text('授权'),
                      ),
              );
            }),
        ],
      );
    });
  }

  /// Linux：经 polkit 给可执行文件补 CAP_NET_ADMIN / CAP_NET_RAW。
  Future<void> _onGrantLinuxCapability(BuildContext context) async {
    await showLinuxCapabilityPrompt(
      context,
      capability: getIt<LinuxCapabilityService>(),
    );
  }

  Future<void> _editVirtualIp(SettingsState settingsState) async {
    final controller = TextEditingController(
      text: settingsState.virtualIp.value,
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑虚拟网络 IP'),
        content: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'IPv4',
              hintText: '例如：$kVirtualIpV4Example',
              prefixIcon: Icon(Icons.lan_outlined),
              border: OutlineInputBorder(),
            ),
            validator: InputValidator.validateIPv4,
            keyboardType: TextInputType.text,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != true || !mounted) return;
    settingsState.virtualIp.value = controller.text.trim();
    await settingsState.saveToPersistence();
  }

  Future<void> _editVirtualIpv6(SettingsState settingsState) async {
    final controller = TextEditingController(
      text: settingsState.virtualIpv6.value,
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑虚拟 IPv6 地址'),
        content: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'IPv6',
              hintText: '例如：$kVirtualIpV6Example',
              prefixIcon: Icon(Icons.public_outlined),
              border: OutlineInputBorder(),
            ),
            validator: InputValidator.validateIPv6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != true || !mounted) return;
    settingsState.virtualIpv6.value = controller.text.trim();
    await settingsState.saveToPersistence();
  }

  Future<void> _onNetworkOptimizeChanged(
    BuildContext context,
    NetworkOptimizeService optimize,
    bool enable,
  ) async {
    try {
      await optimize.setEnabled(enable);
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(context, enable ? '安装失败：$e' : '卸载失败：$e');
    }
  }
}
