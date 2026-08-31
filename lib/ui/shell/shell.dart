import 'package:astral_game/utils/logger.dart';
import 'dart:async';
import 'dart:io';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/services/network_optimize_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/data/services/update_service.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/di.dart' show getIt;
import 'package:astral_game/ui/widgets/bookmark_search_field.dart';
import 'package:astral_game/ui/widgets/edit_profile_dialog.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:signals/signals_flutter.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../pages/dashboard_page.dart';
import '../pages/bookmarks_page.dart';
import '../pages/servers/servers_main_page.dart';
import '../pages/settings/settings_main_page.dart';
import '../widgets/navigation/bottom_nav.dart';
import '../widgets/navigation/left_nav.dart';
import '../widgets/navigation/navigation_item.dart';
import '../widgets/desktop_title_bar.dart';
import '../widgets/mobile_chrome_bar.dart';
import '../widgets/shell_tab_pane.dart';

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
  final bool _isDesktop = RuntimePlatform.isDesktop;
  bool _isMaximized = false;

  /// 收藏 Tab 的索引（[IndexedStack] 顺序：联机/服务器/收藏/设置）。
  static const _bookmarksTabIndex = 2;

  @override
  void initState() {
    super.initState();
    _screenStateService = getIt<ScreenStateService>();

    _shellNavEffect = effect(() {
      final pending = getIt<ShellNavigationService>().pendingTabIndex.value;
      if (pending == null || !mounted) return;
      setState(() => _selectedIndex = pending.clamp(0, 3));
      getIt<ShellNavigationService>().clearPending();
    });

    _navigationItems = [
      const NavigationItem(
        icon: Icons.sports_esports_outlined,
        activeIcon: Icons.sports_esports,
        label: '联机',
        page: DashboardPage(key: PageStorageKey('dashboard')),
      ),
      const NavigationItem(
        icon: Icons.dns_outlined,
        activeIcon: Icons.dns,
        label: '服务器',
        page: ServersMainPage(key: PageStorageKey('servers')),
      ),
      const NavigationItem(
        icon: Icons.bookmark_border_rounded,
        activeIcon: Icons.bookmark_rounded,
        label: '收藏',
        page: BookmarksPage(key: PageStorageKey('bookmarks')),
      ),
      const NavigationItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: '设置',
        page: SettingsMainPage(key: PageStorageKey('settings')),
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // 静默检查更新（业务时序统一封装在 UpdateService 内）
      await getIt<UpdateService>().startAutoCheckIfEnabled(context: context);
      if (!mounted) return;
      // 同步网络加速驱动真实状态，避免设置页首次打开时 installed=false 与实际脱节
      if (RuntimePlatform.isWindows) {
        // ignore: discarded_futures
        getIt<NetworkOptimizeService>().refresh();
      }
    });

    _setupDesktopCloseBehavior();
  }

  @override
  void dispose() {
    _shellNavEffect?.call();
    if (_isDesktop) {
      windowManager.removeListener(this);
      _trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowRestore() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.restore();
    } else {
      await windowManager.maximize();
    }
    // windowManager 的事件会回调 onWindowMaximize/Restore/Unmaximize 自动 setState
  }

  Future<void> _setupDesktopCloseBehavior() async {
    if (!_isDesktop) return;

    windowManager.addListener(this);
    _trayManager.addListener(this);
    await windowManager.setPreventClose(true);
    _isMaximized = await windowManager.isMaximized();
    await _initTray();
  }

  Future<void> _initTray() async {
    final String iconPath;
    if (RuntimePlatform.isWindows) {
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
    if (!RuntimePlatform.isLinux) {
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
      final ext = preferredAssetPath.toLowerCase().endsWith('.ico')
          ? '.ico'
          : '.png';
      return await writeAsset(preferredAssetPath, ext);
    } catch (e) {
      appLogger.w('[Shell] 操作失败', error: e);
      final ext = fallbackAssetPath.toLowerCase().endsWith('.ico')
          ? '.ico'
          : '.png';
      return await writeAsset(fallbackAssetPath, ext);
    }
  }

  Future<void> _showWindowFromTray() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _handleCloseRequested() async {
    if (!_isDesktop) return;
    final closeMinimize = getIt<SettingsState>().closeMinimize.value;
    if (closeMinimize) {
      await windowManager.hide();
      return;
    }
    _quitForReal();
  }

  /// 真正"结束软件"：直接 exit(0)，什么清理都不等，用户点退出就要立刻走。
  void _quitForReal() {
    exit(0);
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
        _quitForReal();
        break;
    }
  }

  void _handleDestinationSelected(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  Widget _buildTabBody(bool isCompact) {
    final pages = [for (final item in _navigationItems) item.page];
    final stack = isCompact
        ? ShellTabStack(index: _selectedIndex, children: pages)
        : IndexedStack(
            index: _selectedIndex,
            sizing: StackFit.expand,
            children: pages,
          );

    if (!isCompact) return stack;

    // 顶栏已处理 status bar，内容区不再叠一层顶部 SafeArea。
    return SafeArea(top: false, bottom: false, child: stack);
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
                    if (_isDesktop)
                      DesktopTitleBar(
                        onClose: () => unawaited(_handleCloseRequested()),
                        isMaximized: _isMaximized,
                        onToggleMaximize: _toggleMaximize,
                        // 收藏 Tab：顶栏中央放搜索胶囊
                        center: _selectedIndex == _bookmarksTabIndex
                            ? const BookmarkSearchField()
                            : null,
                      )
                    // 移动端全宽显示顶栏（平板此前无顶栏，头像/搜索将无处安放）
                    else
                      Watch((context) {
                        return MobileChromeBar(
                          avatar: nodes.currentUserAvatar.value,
                          onAvatarTap: () => showEditProfileDialog(context),
                          // 收藏 Tab：顶栏中央放搜索胶囊
                          center: _selectedIndex == _bookmarksTabIndex
                              ? const BookmarkSearchField()
                              : null,
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
