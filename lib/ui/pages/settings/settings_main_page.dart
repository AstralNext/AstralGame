
import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/data/state/update_state.dart';
import 'package:astral_game/data/state/theme_reveal_state.dart';
import 'package:astral_game/ui/widgets/astral_settings_section.dart';
import 'package:astral_game/ui/widgets/fade_in_section.dart';
import 'package:astral_game/ui/navigation/astral_page_route.dart';
import 'package:astral_game/ui/widgets/theme_picker_sheet.dart';
import 'package:astral_game/data/services/floating_overlay_service.dart';
import 'package:astral_game/data/services/network_optimize_service.dart';
import 'package:astral_game/utils/input_validator.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import 'about_page.dart';
import 'vpn_routes_page.dart';

/// 设置主页面。
class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({super.key});

  @override
  State<SettingsMainPage> createState() => _SettingsMainPageState();
}

class _SettingsMainPageState extends State<SettingsMainPage> {
  static const _tilePadding = EdgeInsets.symmetric(horizontal: 16);

  static bool get _isDesktop {
    final os = RuntimePlatform.operatingSystem;
    return os != 'android' && os != 'ios';
  }

  static bool get _isAndroid => RuntimePlatform.isAndroid;

  late TextEditingController _virtualIpController;
  late bool _isDhcp;
  bool _isValidIP = true;

  @override
  void initState() {
    super.initState();
    final appSettings = getIt<AppSettingsService>();
    _isDhcp = appSettings.getIsDhcp();
    _virtualIpController =
        TextEditingController(text: appSettings.getVirtualIp());
  }

  @override
  void dispose() {
    _virtualIpController.dispose();
    super.dispose();
  }

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
            children: [
              if (_isDesktop) ...[
                Watch((context) {
                  return _buildSwitchTile(
                    title: '关闭时最小化到托盘',
                    subtitle: '点击关闭时最小化到托盘区',
                    value: settingsState.closeMinimize.value,
                    onChanged: (v) {
                      settingsState.closeMinimize.value = v;
                      settingsState.saveToPersistence();
                    },
                  );
                }),
                const Divider(height: 1),
              ],
              Watch((context) {
                return _buildSwitchTile(
                  title: '自动检查更新',
                  value: updateState.autoCheckUpdate.value,
                  onChanged: updateState.setAutoCheckUpdate,
                );
              }),
              const Divider(height: 1),
              Watch((context) {
                return _buildSwitchTile(
                  title: '测试版频道',
                  value: updateState.beta.value,
                  onChanged: updateState.setBeta,
                );
              }),
              if (_isAndroid) ...[
                const Divider(height: 1),
                Watch((context) {
                  return _buildSwitchTile(
                    title: '在线用户悬浮窗',
                    subtitle: '透明 HUD，不挡触摸；显示头像、IP、延迟列表',
                    value: settingsState.floatingOverlayEnabled.value,
                    onChanged: (v) => _onFloatingOverlayChanged(
                      context,
                      settingsState,
                      v,
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.sectionGap),
        FadeInSection(
          order: 2,
          child: _buildNetworkSection(settingsState),
        ),
        const SizedBox(height: AppDimensions.sectionGap),
        FadeInSection(
          order: 3,
          child: AstralSettingsSection(
            title: '其他',
            items: [
              AstralSettingItem(
                icon: Icons.info_outline_rounded,
                label: '关于 Astral Game',
                onTap: () => Navigator.of(context).push<void>(
                  astralPageRoute(const AboutPage()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
      final goSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要悬浮窗权限'),
          content: const Text(
            '请在系统设置中允许 Astral Game「显示在其他应用上层」，'
            '然后返回应用重新打开此开关。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      if (goSettings == true) {
        await overlay.openOverlayPermissionSettings();
      }
      settingsState.floatingOverlayEnabled.value = false;
      await settingsState.saveToPersistence();
      return;
    }

    await overlay.show();
  }

  Widget _buildNetworkSection(SettingsState settingsState) {
    final textTheme = Theme.of(context).textTheme;
    return AstralSettingsFormCard(
      title: '网络',
      children: [
        _buildSwitchTile(
          title: '自动分配虚拟网络 IP',
          subtitle: _isDhcp ? 'DHCP 已开启' : '关闭后可手动填写固定 IP',
          value: _isDhcp,
          onChanged: (value) {
            setState(() {
              _isDhcp = value;
              if (value) _isValidIP = true;
            });
            getIt<AppSettingsService>().setIsDhcp(value);
          },
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: TextField(
            controller: _virtualIpController,
            enabled: !_isDhcp,
            onChanged: (value) {
              if (!_isDhcp) {
                setState(() {
                  _isValidIP = InputValidator.validateIPv4(value) == null;
                });
                if (_isValidIP) {
                  getIt<AppSettingsService>().setVirtualIp(value);
                }
              }
            },
            decoration: InputDecoration(
              labelText: '虚拟网络 IP',
              hintText: '10.147.xxx.xxx',
              prefixIcon: const Icon(Icons.lan_outlined),
              helperText: _isDhcp ? '开启 DHCP 时会自动分配' : null,
              errorText: (!_isDhcp && !_isValidIP) ? '无效的 IPv4 地址' : null,
            ),
          ),
        ),
        if (_isDhcp)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '当前为自动分配模式。',
              style: textTheme.bodySmall,
            ),
          ),
        const Divider(height: 1),
        Watch((context) {
          return _buildSwitchTile(
            title: '禁用 P2P',
            subtitle: '仅通过中继通信',
            value: settingsState.disableP2p.value,
            onChanged: (v) {
              settingsState.disableP2p.value = v;
              settingsState.saveToPersistence();
            },
          );
        }),
        if (RuntimePlatform.operatingSystem == 'windows') ...[
          const Divider(height: 1),
          Watch((context) {
            return _buildSwitchTile(
              title: '强制 UDP 广播转发',
              subtitle: '覆盖游戏规则；多数游戏由线上规则自动开启，重连后生效',
              value: settingsState.enableUdpBroadcastRelay.value,
              onChanged: (v) {
                settingsState.enableUdpBroadcastRelay.value = v;
                settingsState.saveToPersistence();
              },
            );
          }),
          const Divider(height: 1),
          Watch((context) {
            final optimize = getIt<NetworkOptimizeService>();
            final busy = optimize.busy.value;
            return _buildSwitchTile(
              title: '网络加速（仅限中国大陆）',
              subtitle: busy
                  ? '正在安装或卸载…'
                  : '自动选择最低延迟的网址 IP',
              value: optimize.installed.value,
              onChanged: busy
                  ? null
                  : (v) => _onNetworkOptimizeChanged(context, optimize, v),
            );
          }),
        ],
        if (_isAndroid) ...[
          const Divider(height: 1),
          ListTile(
            contentPadding: _tilePadding,
            leading: const Icon(Icons.route_outlined),
            title: const Text('自定义 VPN 路由'),
            subtitle: const Text('额外 CIDR；默认含虚拟网段、组播、广播'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push<void>(
              astralPageRoute(const VpnRoutesPage()),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: _tilePadding,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enable ? '安装失败：$e' : '卸载失败：$e')),
      );
    }
  }
}
