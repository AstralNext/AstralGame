import 'dart:async';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/data/state/update_state.dart';
import 'package:astral_game/data/state/theme_reveal_state.dart';
import 'package:astral_game/ui/widgets/app_toast.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/astral_grouped_tile.dart';
import 'package:astral_game/ui/widgets/astral_settings_section.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:astral_game/ui/widgets/bookmark_card.dart';
import 'package:astral_game/ui/widgets/confirm_dialog.dart';
import 'package:astral_game/ui/widgets/edit_profile_dialog.dart';
import 'package:astral_game/ui/widgets/fade_in_section.dart';
import 'package:astral_game/ui/widgets/linux_capability_prompt.dart';
import 'package:astral_game/ui/navigation/astral_page_route.dart';
import 'package:astral_game/ui/widgets/theme_picker_sheet.dart';
import 'package:astral_game/data/services/firewall_service.dart';
import 'package:astral_game/data/services/floating_overlay_service.dart';
import 'package:astral_game/data/services/linux_capability_service.dart';
import 'package:astral_game/data/services/network_optimize_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/windows_settings_service.dart';
import 'package:astral_game/utils/input_validator.dart';
import 'package:astral_game/utils/room_display.dart';
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
  const SettingsMainPage({super.key, this.scrollController});

  /// Shell 注入的滚动控制器：重按当前 Tab 时用它回到顶部。
  final ScrollController? scrollController;

  @override
  State<SettingsMainPage> createState() => _SettingsMainPageState();
}

class _SettingsMainPageState extends State<SettingsMainPage>
    with WidgetsBindingObserver {
  static bool get _isDesktop {
    final os = RuntimePlatform.operatingSystem;
    return os != 'android' && os != 'ios';
  }

  static bool get _isAndroid => RuntimePlatform.isAndroid;

  /// 已跳转系统悬浮窗授权页，等待返回后复查权限。
  bool _awaitingOverlayPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (RuntimePlatform.isWindows) {
      unawaited(getIt<FirewallService>().refreshAllProfiles());
      unawaited(getIt<WindowsSettingsService>().refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_awaitingOverlayPermission) {
      return;
    }
    _awaitingOverlayPermission = false;
    unawaited(_applyOverlayPermissionResult());
  }

  Future<void> _applyOverlayPermissionResult() async {
    final overlay = FloatingOverlayService();
    if (await overlay.canDrawOverlays()) {
      await overlay.show();
      return;
    }
    final settingsState = getIt<SettingsState>();
    settingsState.floatingOverlayEnabled.value = false;
    await settingsState.saveToPersistence();
    if (!mounted) return;
    showAppToast(context, '未获得悬浮窗权限，已关闭悬浮窗');
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = getIt<SettingsState>();
    final updateState = getIt<UpdateState>();
    final nodeManagement = getIt<NodeManagementService>();
    final isNarrow = MediaQuery.sizeOf(context).width < AppBreakpoints.narrow;
    // 宽屏有悬浮侧栏：左侧收紧贴近胶囊，右侧仍保持常规页边距。
    final startPad = isNarrow
        ? AppDimensions.pagePaddingHMobile
        : AppDimensions.pagePaddingHWithSideNav;
    final endPad = isNarrow
        ? AppDimensions.pagePaddingHMobile
        : AppDimensions.pagePaddingH;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: EdgeInsetsDirectional.fromSTEB(
              startPad,
              12,
              endPad,
              // 悬浮胶囊高度 + 系统底部安全区，避免最后一项被手势条/胶囊压住。
              AppDimensions.listBottomWithNav(context),
            ),
            children: [
              FadeInSection(
                child: Watch((context) {
                  final username = nodeManagement.currentUsername.value.trim();
                  final palette = context.astralPalette;
                  return AstralCard(
                    onTap: () => showEditProfileDialog(context),
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      children: [
                        AvatarWidget(
                          avatar: nodeManagement.currentUserAvatar.value,
                          size: 56,
                          showBorder: false,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                username.isEmpty ? '玩家' : username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '点击修改头像和昵称',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: palette.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: palette.textSecondary,
                        ),
                      ],
                    ),
                  );
                }),
              ),
              const SizedBox(height: AppDimensions.sectionGap),
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
                child: Watch((context) {
                  return AstralSettingsFormCard(
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
                        icon: Icons.login_rounded,
                        title: '启动后自动进入房间',
                        subtitle: () => '从收藏中选择要进入的房间',
                        value: () => settingsState.autoEnterRoom.value,
                        onChanged: (v) =>
                            _onAutoEnterRoomChanged(settingsState, v),
                      ),
                      if (settingsState.autoEnterRoom.value)
                        (index, count) =>
                            _buildAutoEnterRoomRow(settingsState, index, count),
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
                          value: () =>
                              settingsState.floatingOverlayEnabled.value,
                          onChanged: (v) => _onFloatingOverlayChanged(
                            context,
                            settingsState,
                            v,
                          ),
                        ),
                    ],
                  );
                }),
              ),
              if (RuntimePlatform.isWindows) ...[
                const SizedBox(height: AppDimensions.sectionGap),
                FadeInSection(
                  order: 2,
                  child: _buildWindowsSection(settingsState),
                ),
              ],
              const SizedBox(height: AppDimensions.sectionGap),
              FadeInSection(
                order: 3,
                child: _buildNetworkSection(settingsState),
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
                      onTap: () => Navigator.of(
                        context,
                      ).push<void>(astralPageRoute(const AboutPage())),
                    ),
                  ],
                ),
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
    bool Function()? enabled,
  }) {
    return (index, count) => Watch((context) {
      final v = value();
      final editable = enabled?.call() ?? true;
      return AstralGroupedTile(
        icon: icon,
        label: title,
        subtitle: subtitle?.call(),
        index: index,
        count: count,
        onTap: onChanged == null || !editable ? null : () => onChanged(!v),
        trailing: Switch.adaptive(
          value: v,
          onChanged: editable ? onChanged : null,
        ),
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
            '返回后会自动开启悬浮窗。',
        confirmLabel: '去设置',
      );
      if (goSettings) {
        // 保持开关开启，返回应用后复查权限并自动显示，无需再次手动打开。
        _awaitingOverlayPermission = true;
        await overlay.openOverlayPermissionSettings();
        return;
      }
      settingsState.floatingOverlayEnabled.value = false;
      await settingsState.saveToPersistence();
      return;
    }

    await overlay.show();
  }

  Widget _buildNetworkSection(SettingsState settingsState) {
    return Watch((context) {
      final roomState = getIt<RoomState>();
      final isDhcp = settingsState.isDhcp.value;
      final virtualIp = settingsState.virtualIp.value;
      final virtualIpv6 = settingsState.virtualIpv6.value;
      final canEditNetwork = !roomState.isConnected.value;
      String changeableHint(String text) =>
          canEditNetwork ? '$text，更改后需重启房间生效' : '$text，更改后需重启房间生效；连接中不可修改';
      return AstralSettingsFormCard(
        title: '网络',
        rows: [
          if (RuntimePlatform.isWindows)
            (index, count) => Watch((context) {
              final firewall = getIt<FirewallService>();
              final disabled = firewall.allProfilesDisabled.value == true;
              final busy = firewall.busy.value;
              final toggle = busy
                  ? null
                  : (bool value) => _onToggleAllFirewall(firewall, !value);
              return AstralGroupedTile(
                icon: Icons.gpp_maybe_outlined,
                label: '关闭防火墙',
                subtitle: disabled ? '当前已关闭' : '当前已开启',
                index: index,
                count: count,
                onTap: toggle == null ? null : () => toggle(!disabled),
                trailing: Switch.adaptive(value: disabled, onChanged: toggle),
              );
            }),
          _switchRow(
            icon: Icons.hub_outlined,
            title: '禁用 P2P',
            subtitle: () => changeableHint('仅通过中继通信'),
            value: () => settingsState.disableP2p.value,
            enabled: () => canEditNetwork,
            onChanged: (v) {
              settingsState.disableP2p.value = v;
              settingsState.saveToPersistence();
            },
          ),
          (index, count) => AstralGroupedTile(
            icon: Icons.speed_outlined,
            label: '网络测速',
            subtitle: '测试延迟与上下行速度',
            index: index,
            count: count,
            onTap: () => Navigator.of(
              context,
            ).push<void>(astralPageRoute(const SpeedTestPage())),
          ),
          if (RuntimePlatform.isWindows)
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
          _switchRow(
            icon: Icons.settings_ethernet_outlined,
            title: '自动分配虚拟IP',
            subtitle: () => changeableHint('关闭后可手动设置虚拟 IP'),
            value: () => settingsState.isDhcp.value,
            enabled: () => canEditNetwork,
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

  /// Windows 专属：开机启动与 UAC。注册表为唯一真实状态。
  Widget _buildWindowsSection(SettingsState settingsState) {
    return Watch((context) {
      final win = getIt<WindowsSettingsService>();
      final autoStart = win.autoStart.value;
      final autoStartOn = autoStart ?? false;
      final busy = win.busy.value;
      final uacEnabled = win.uacEnabled.value;
      final toggleAutoStart = autoStart == null || busy
          ? null
          : (bool value) => _onAutoStartChanged(win, value);
      final toggleUac = uacEnabled == null || busy
          ? null
          : (bool value) => _onUacChanged(win, disable: value);

      return AstralSettingsFormCard(
        title: 'Windows',
        rows: [
          (index, count) => AstralGroupedTile(
            icon: Icons.power_settings_new_outlined,
            label: '开机启动',
            subtitle: busy ? '正在应用…' : '登录 Windows 后自动启动 Astral Game',
            index: index,
            count: count,
            onTap: toggleAutoStart == null
                ? null
                : () => toggleAutoStart(!autoStartOn),
            trailing: Switch.adaptive(
              value: autoStartOn,
              onChanged: toggleAutoStart,
            ),
          ),
          if (autoStartOn)
            _switchRow(
              icon: Icons.vertical_align_bottom_rounded,
              title: '启动后到托盘',
              subtitle: () => '仅开机启动时生效，不显示主窗口',
              value: () => settingsState.startToTray.value,
              onChanged: (v) {
                settingsState.startToTray.value = v;
                settingsState.saveToPersistence();
              },
            ),
          (index, count) => AstralGroupedTile(
            icon: Icons.admin_panel_settings_outlined,
            label: '关闭 UAC',
            subtitle: uacEnabled == null
                ? '无法读取当前状态'
                : uacEnabled
                ? '更改设置后需重启系统生效'
                : '更改设置后需重启系统生效',
            index: index,
            count: count,
            onTap: toggleUac == null
                ? null
                : () => toggleUac(uacEnabled != true),
            trailing: Switch.adaptive(
              value: uacEnabled == false,
              onChanged: toggleUac,
            ),
          ),
        ],
      );
    });
  }

  /// 「启动后自动进入房间」下方的房间选择行：展示当前选中的收藏。
  Widget _buildAutoEnterRoomRow(
    SettingsState settingsState,
    int index,
    int count,
  ) {
    final bookmarks = getIt<RoomState>().bookmarks;
    final selectedId = settingsState.autoEnterBookmarkId.value;
    Bookmark? selected;
    for (final bookmark in bookmarks) {
      if (bookmark.id == selectedId) {
        selected = bookmark;
        break;
      }
    }
    final subtitle = selected != null
        ? selected.displayName
        : selectedId == null
        ? '未选择，点击从收藏中选择'
        : '对应收藏已删除，请重新选择';
    return AstralGroupedTile(
      icon: Icons.star_outline_rounded,
      label: '进入的房间',
      subtitle: subtitle,
      index: index,
      count: count,
      onTap: () => _pickAutoEnterBookmark(settingsState),
    );
  }

  Future<void> _onAutoEnterRoomChanged(
    SettingsState settingsState,
    bool enabled,
  ) async {
    if (!enabled) {
      settingsState.autoEnterRoom.value = false;
      await settingsState.saveToPersistence();
      return;
    }

    final bookmarks = getIt<RoomState>().bookmarks;
    if (bookmarks.isEmpty) {
      showAppToast(context, '暂无收藏房间，请先在收藏页收藏房间');
      return;
    }

    // 首次开启或原收藏已删除：先选房间，取消选择则保持关闭。
    final selectedId = settingsState.autoEnterBookmarkId.value;
    if (!bookmarks.any((b) => b.id == selectedId)) {
      final picked = await _showBookmarkPickerDialog(bookmarks, selectedId);
      if (picked == null || !mounted) return;
      settingsState.autoEnterBookmarkId.value = picked;
    }

    settingsState.autoEnterRoom.value = true;
    await settingsState.saveToPersistence();
  }

  Future<void> _pickAutoEnterBookmark(SettingsState settingsState) async {
    final bookmarks = getIt<RoomState>().bookmarks;
    if (bookmarks.isEmpty) {
      showAppToast(context, '暂无收藏房间，请先在收藏页收藏房间');
      return;
    }
    final picked = await _showBookmarkPickerDialog(
      bookmarks,
      settingsState.autoEnterBookmarkId.value,
    );
    if (picked == null || !mounted) return;
    settingsState.autoEnterBookmarkId.value = picked;
    await settingsState.saveToPersistence();
  }

  /// 从收藏中选择启动后要进入的房间，返回收藏 id（只展示封面与名字）。
  Future<int?> _showBookmarkPickerDialog(
    List<Bookmark> bookmarks,
    int? currentId,
  ) {
    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('选择启动后进入的房间'),
          content: SizedBox(
            width: 420,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: bookmarks.length,
                itemBuilder: (context, i) {
                  final bookmark = bookmarks[i];
                  final selected = bookmark.id == currentId;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(
                      width: 40,
                      height: 40,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: BookmarkCover(bookmark: bookmark),
                      ),
                    ),
                    title: Text(
                      bookmarkDisplayLabel(bookmark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: selected
                        ? Icon(Icons.check_rounded, color: scheme.primary)
                        : null,
                    onTap: () => Navigator.of(dialogContext).pop(bookmark.id),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onAutoStartChanged(
    WindowsSettingsService win,
    bool enabled,
  ) async {
    final ok = await win.setAutoStart(enabled);
    if (!mounted || ok) return;
    showAppToast(context, enabled ? '开启开机启动失败' : '关闭开机启动失败');
  }

  /// [disable] 为 true 表示关闭 UAC（EnableLUA = 0）。
  Future<void> _onUacChanged(
    WindowsSettingsService win, {
    required bool disable,
  }) async {
    if (disable) {
      final confirmed = await showConfirmDialog(
        context,
        title: '关闭 UAC？',
        content:
            '关闭用户账户控制后，应用修改系统设置时不再弹出确认框，'
            '但系统安全性会降低。更改将在重启后生效。',
        confirmLabel: '关闭',
      );
      if (!confirmed) return;
    }
    final ok = await win.setUacEnabled(!disable);
    if (!mounted) return;
    showAppToast(context, ok ? '已保存，重启后生效' : '修改 UAC 设置失败');
  }

  /// Linux：经 polkit 给可执行文件补 CAP_NET_ADMIN / CAP_NET_RAW。
  Future<void> _onGrantLinuxCapability(BuildContext context) async {
    await showLinuxCapabilityPrompt(
      context,
      capability: getIt<LinuxCapabilityService>(),
    );
  }

  /// Windows：一键关闭 / 恢复域、专用、公用三个防火墙配置文件。
  Future<void> _onToggleAllFirewall(
    FirewallService firewall,
    bool enable,
  ) async {
    await firewall.setAllProfilesFirewallStatus(enable);
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
      showAppToast(context, enable ? '安装失败：$e' : '卸载失败：$e');
    }
  }
}
