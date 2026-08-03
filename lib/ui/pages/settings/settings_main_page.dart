import 'dart:io';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/data/state/update_state.dart';
import 'package:astral_game/data/state/theme_reveal_state.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/astral_settings_section.dart';
import 'package:astral_game/ui/widgets/fade_in_section.dart';
import 'package:astral_game/ui/navigation/astral_page_route.dart';
import 'package:astral_game/ui/widgets/theme_picker_sheet.dart';
import 'package:astral_game/data/services/floating_overlay_service.dart';
import 'package:astral_game/utils/input_validator.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import 'about_page.dart';
import 'cloud_backup_settings_page.dart';

/// 设置主页面；云备份与关于为独立子页。
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

  static bool get _isAndroid => Platform.isAndroid;

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
          order: 0,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(context, '应用'),
              AstralCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (_isDesktop) ...[
                      Watch((context) {
                        return SwitchListTile(
                          title: const Text('关闭时最小化到托盘'),
                          subtitle: const Text('点击关闭时最小化到托盘区'),
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
                      return SwitchListTile(
                        title: const Text('自动检查更新'),
                        value: updateState.autoCheckUpdate.value,
                        onChanged: updateState.setAutoCheckUpdate,
                      );
                    }),
                    const Divider(height: 1),
                    Watch((context) {
                      return SwitchListTile(
                        title: const Text('测试版频道'),
                        value: updateState.beta.value,
                        onChanged: updateState.setBeta,
                      );
                    }),
                    if (_isAndroid) ...[
                      const Divider(height: 1),
                      Watch((context) {
                        return SwitchListTile(
                          title: const Text('在线用户悬浮窗'),
                          subtitle: const Text('透明 HUD，不挡触摸；显示头像、IP、延迟列表'),
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
            title: '数据',
            items: [
              AstralSettingItem(
                icon: Icons.cloud_upload_outlined,
                label: '云备份',
                subtitle: 'WebDAV 备份与恢复',
                onTap: () => Navigator.of(context).push<void>(
                  astralPageRoute(const CloudBackupSettingsPage()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.sectionGap),
        FadeInSection(
          order: 4,
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
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      if (goSettings == true) {
        await overlay.openOverlayPermissionSettings();
      }
      return;
    }

    await overlay.applyFromAppState();
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: context.astralPalette.accent,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
      ),
    );
  }

  Widget _buildNetworkSection(SettingsState settingsState) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(context, '网络'),
        AstralCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _virtualIpController,
                      enabled: !_isDhcp,
                      onChanged: (value) {
                        if (!_isDhcp) {
                          setState(() {
                            _isValidIP =
                                InputValidator.validateIPv4(value) == null;
                          });
                          if (_isValidIP) {
                            getIt<AppSettingsService>().setVirtualIp(value);
                          }
                        }
                      },
                      decoration: InputDecoration(
                        labelText: '虚拟网络 IP',
                        hintText: '10.147.xxx.xxx',
                        prefixIcon: Icon(
                          Icons.lan_outlined,
                          color: colorScheme.primary,
                        ),
                        errorText: (!_isDhcp && !_isValidIP)
                            ? '无效的 IPv4 地址'
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      Switch(
                        value: _isDhcp,
                        onChanged: (value) {
                          setState(() => _isDhcp = value);
                          getIt<AppSettingsService>().setIsDhcp(value);
                        },
                      ),
                      Text(_isDhcp ? '自动' : '手动', style: textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
              if (_isDhcp)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'IP 将由服务器自动分配',
                    style: textTheme.bodySmall,
                  ),
                ),
              const Divider(height: 24),
              Watch((context) {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('禁用 P2P'),
                  subtitle: const Text('仅通过中继通信'),
                  value: settingsState.disableP2p.value,
                  onChanged: (v) {
                    settingsState.disableP2p.value = v;
                    settingsState.saveToPersistence();
                  },
                );
              }),
              if (RuntimePlatform.operatingSystem == 'windows')
                Watch((context) {
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('UDP 广播转发'),
                    subtitle: const Text('局域网发现；重连后生效'),
                    value: settingsState.enableUdpBroadcastRelay.value,
                    onChanged: (v) {
                      settingsState.enableUdpBroadcastRelay.value = v;
                      settingsState.saveToPersistence();
                    },
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}
