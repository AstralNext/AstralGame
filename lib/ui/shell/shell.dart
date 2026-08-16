import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/data/services/update_service.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/data/state/update_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:astral_game/ui/widgets/edit_profile_dialog.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../pages/dashboard_page.dart';
import '../pages/servers/servers_main_page.dart';
import '../pages/settings/settings_main_page.dart';
import '../widgets/navigation/bottom_nav.dart';
import '../widgets/navigation/left_nav.dart';
import '../widgets/navigation/navigation_item.dart';
import '../widgets/shell_tab_pane.dart';
import '../widgets/window_button.dart';

/// 主壳：底栏 / 侧栏切换 Tab（[IndexedStack]），二级页走根 [Navigator] + [AppBar] 返回。
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WindowListener, TrayListener {
  late final ScreenStateService _screenStateService;
  late final List<NavigationItem> _navigationItems;
  final TrayManager _trayManager = TrayManager.instance;
  EffectCleanup? _shellNavEffect;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _screenStateService = getIt<ScreenStateService>();

    _shellNavEffect = effect(() {
      final pending = getIt<ShellNavigationService>().pendingTabIndex.value;
      if (pending == null || !mounted) return;
      setState(() => _selectedIndex = pending.clamp(0, 2));
      getIt<ShellNavigationService>().clearPending();
    });

    _navigationItems = [
      NavigationItem(
        icon: Icons.sports_esports_outlined,
        activeIcon: Icons.sports_esports,
        label: '联机',
        page: const DashboardPage(key: PageStorageKey('dashboard')),
      ),
      NavigationItem(
        icon: Icons.dns_outlined,
        activeIcon: Icons.dns,
        label: '服务器',
        page: const ServersMainPage(key: PageStorageKey('servers')),
      ),
      NavigationItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: '设置',
        page: const SettingsMainPage(key: PageStorageKey('settings')),
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _screenStateService.updateScreenWidth(MediaQuery.sizeOf(context).width);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final updateState = getIt<UpdateState>();
        if (updateState.autoCheckUpdate.value) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              getIt<UpdateService>().checkForUpdates(
                context,
                showNoUpdateMessage: false,
                showFailureMessage: false,
              );
            }
          });
        }
      }
    });

    _setupDesktopCloseBehavior();
  }

  @override
  void dispose() {
    _shellNavEffect?.call();
    if (_isDesktopPlatform) {
      windowManager.removeListener(this);
      _trayManager.removeListener(this);
    }
    super.dispose();
  }

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _setupDesktopCloseBehavior() async {
    if (!_isDesktopPlatform) return;

    windowManager.addListener(this);
    _trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    await _initTray();
  }

  Future<void> _initTray() async {
    final String iconPath;
    if (Platform.isWindows) {
      iconPath = await _ensureTrayIconFile(
        preferredAssetPath: 'assets/icon.ico',
        fallbackAssetPath: 'assets/logo.png',
        outputFileName: 'astral_game_tray_icon_bw',
      );
    } else {
      iconPath = await _ensureTrayIconFile(
        preferredAssetPath: 'assets/logo.png',
        fallbackAssetPath: 'assets/logo.png',
        outputFileName: 'astral_game_tray_icon_bw',
      );
    }

    await _trayManager.setIcon(iconPath);
    if (!Platform.isLinux) {
      await _trayManager.setToolTip('Astral Game');
    }
    await _trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: '显示主界面'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
  }

  Future<String> _ensureTrayIconFile({
    required String preferredAssetPath,
    required String fallbackAssetPath,
    required String outputFileName,
  }) async {
    final tmpDir = await getTemporaryDirectory();

    Future<String> writeAsset(String assetPath, String ext) async {
      final bytes = await rootBundle.load(assetPath);
      final file = File(
        '${tmpDir.path}${Platform.pathSeparator}$outputFileName$ext',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      return file.path;
    }

    try {
      final ext =
          preferredAssetPath.toLowerCase().endsWith('.ico') ? '.ico' : '.png';
      return await writeAsset(preferredAssetPath, ext);
    } catch (_) {
      final ext =
          fallbackAssetPath.toLowerCase().endsWith('.ico') ? '.ico' : '.png';
      return await writeAsset(fallbackAssetPath, ext);
    }
  }

  Future<void> _showWindowFromTray() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _handleCloseRequested() async {
    if (!_isDesktopPlatform) return;
    final closeMinimize = getIt<SettingsState>().closeMinimize.value;
    if (closeMinimize) {
      await windowManager.hide();
      return;
    }
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() {
    unawaited(_handleCloseRequested());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindowFromTray());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(_showWindowFromTray());
        break;
      case 'exit':
        unawaited(() async {
          await windowManager.setPreventClose(false);
          await windowManager.close();
        }());
        break;
    }
  }

  void _handleDestinationSelected(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  Widget _buildTabBody(bool isCompact) {
    final pages = [
      for (final item in _navigationItems) item.page,
    ];
    final stack = isCompact
        ? ShellTabStack(index: _selectedIndex, children: pages)
        : IndexedStack(
            index: _selectedIndex,
            sizing: StackFit.expand,
            children: pages,
          );

    if (!isCompact) return stack;

    // 顶栏已处理 status bar，内容区不再叠一层顶部 SafeArea。
    return SafeArea(
      top: false,
      bottom: false,
      child: stack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;
    _screenStateService.updateScreenWidth(screenWidth);
    final nodes = getIt<NodeManagementService>();

    final contentRadius = isCompact
        ? BorderRadius.circular(AppDimensions.radiusMd)
        : const BorderRadius.only(
            topLeft: Radius.circular(AppDimensions.radiusMd),
          );

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: palette.canvas,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isCompact)
              ColoredBox(
                color: palette.canvas,
                child: Watch((context) {
                  return LeftNav(
                    items: _navigationItems,
                    selectedIndex: _selectedIndex,
                    onSelected: _handleDestinationSelected,
                    avatar: nodes.currentUserAvatar.value,
                    username: nodes.currentUsername.value,
                    onAvatarTap: () => showEditProfileDialog(context),
                  );
                }),
              ),
            Expanded(
              child: ColoredBox(
                color: palette.canvas,
                child: Column(
                  children: [
                    if (_isDesktopPlatform)
                      _DesktopTitleBar(
                        onClose: () => unawaited(_handleCloseRequested()),
                      )
                    else if (isCompact)
                      Watch((context) {
                        return _MobileChromeBar(
                          avatar: nodes.currentUserAvatar.value,
                          onAvatarTap: () => showEditProfileDialog(context),
                        );
                      }),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: contentRadius,
                        child: ColoredBox(
                          color: palette.background,
                          child: _buildTabBody(isCompact),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: isCompact
            ? ColoredBox(
                color: palette.canvas,
                child: SafeArea(
                  top: false,
                  child: BottomNav(
                    navigationItems: _navigationItems,
                    selectedIndex: _selectedIndex,
                    onSelected: _handleDestinationSelected,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// 手机顶栏：模拟桌面标题栏，头像落在窗口按钮区域。
class _MobileChromeBar extends StatelessWidget {
  const _MobileChromeBar({
    required this.avatar,
    required this.onAvatarTap,
  });

  final Uint8List? avatar;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    return Material(
      color: palette.canvas,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Astral Game',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AvatarWidget(
                  avatar: avatar,
                  size: 36,
                  shape: AvatarShape.circle,
                  onTap: onAvatarTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌面窗口标题栏（仅拖拽与窗口按钮，不参与页面返回）。
class _DesktopTitleBar extends StatefulWidget {
  const _DesktopTitleBar({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<_DesktopTitleBar> {
  bool _isMaximized = false;

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.restore();
      setState(() => _isMaximized = false);
    } else {
      await windowManager.maximize();
      setState(() => _isMaximized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: SizedBox(
        height: 44,
        child: Container(
          color: palette.canvas,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Astral Game',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              WindowButton(
                icon: Icons.remove,
                iconSize: 16,
                hoverColor: palette.accentMuted,
                iconColor: palette.textPrimary,
                onTap: () => windowManager.minimize(),
              ),
              WindowButton(
                icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                iconSize: 14,
                hoverColor: palette.accentMuted,
                iconColor: palette.textPrimary,
                onTap: () => unawaited(_toggleMaximize()),
              ),
              WindowButton(
                icon: Icons.close,
                iconSize: 16,
                hoverColor: palette.error.withValues(alpha: 0.2),
                iconColor: palette.textPrimary,
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
