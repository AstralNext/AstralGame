import 'package:astral_game/utils/logger.dart';
import 'dart:async';
import 'dart:io';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/firewall_service.dart';
import 'package:astral_game/data/services/join_link_service.dart';
import 'package:astral_game/data/services/network_optimize_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/data/services/update_service.dart';
import 'package:astral_game/data/state/bookmark_search_state.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/di.dart' show getIt;
import 'package:astral_game/ui/widgets/app_toast.dart';
import 'package:astral_game/ui/widgets/bookmark_search_field.dart';
import 'package:astral_game/ui/widgets/edit_profile_dialog.dart';
import 'package:astral_game/utils/error_text.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:signals/signals_flutter.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../pages/dashboard_page.dart';
import '../pages/bookmarks_page.dart';
import '../pages/servers/server_dialog.dart';
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

  /// 手机端收藏搜索是否展开（底部搜索胶囊）。
  bool _bookmarkSearchOpen = false;

  /// 收藏 Tab 的索引（[IndexedStack] 顺序：联机/服务器/收藏/设置）。
  static const _bookmarksTabIndex = 2;

  /// 服务器 Tab 的索引。
  static const _serversTabIndex = 1;

  /// 设置 Tab 的索引。
  static const _settingsTabIndex = 3;

  @override
  void initState() {
    super.initState();
    _screenStateService = getIt<ScreenStateService>();

    _shellNavEffect = effect(() {
      final pending = getIt<ShellNavigationService>().pendingTabIndex.value;
      if (pending == null || !mounted) return;
      final index = pending.clamp(0, 3);
      if (index != _bookmarksTabIndex && _bookmarkSearchOpen) {
        _closeBookmarkSearch();
      }
      setState(() => _selectedIndex = index);
      if (_selectedIndex == _settingsTabIndex) _refreshFirewallStatus();
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
      // 首次启动且从未设置昵称：先引导设置头像与昵称。
      if (getIt<AppSettingsService>().needsProfileSetup()) {
        await showEditProfileDialog(context, onboarding: true);
        if (!mounted) return;
      }
      // 自动进入设定好的收藏房间：先于更新检查发起，避免被网络检查拖住。
      unawaited(_autoEnterSelectedRoomIfNeeded());
      // 静默检查更新（业务时序统一封装在 UpdateService 内）
      unawaited(
        getIt<UpdateService>().startAutoCheckIfEnabled(context: context),
      );
      // 同步网络加速驱动真实状态，避免设置页首次打开时 installed=false 与实际脱节
      if (RuntimePlatform.isWindows) {
        // ignore: discarded_futures
        getIt<NetworkOptimizeService>().refresh();
      }
    });

    _setupDesktopCloseBehavior();
  }

  /// 启动后自动进入设定好的收藏房间（全平台生效）。
  Future<void> _autoEnterSelectedRoomIfNeeded() async {
    if (!mounted) return;
    final settingsState = getIt<SettingsState>();
    if (!settingsState.autoEnterRoom.value) return;

    // 与 URL 邀请链接进房协作：若是通过链接拉起（全平台），交给 JoinLinkBinder，
    // 避免两边同时进房。等待首次链接探测完成，避免异步竞态。
    final joinLinks = getIt<JoinLinkService>();
    try {
      await joinLinks.initialLinkReady.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // 探测超时（平台不支持等情况）：按普通启动处理。
    }
    if (!mounted) return;
    if (joinLinks.hadInitialLink || joinLinks.pendingToken.value != null) {
      return;
    }

    final roomState = getIt<RoomState>();
    if (roomState.session.value != null) return;

    final bookmarkId = settingsState.autoEnterBookmarkId.value;
    RoomInvitePayload? payload;
    if (bookmarkId != null) {
      for (final bookmark in roomState.bookmarks) {
        if (bookmark.id == bookmarkId) {
          payload = bookmark.payload;
          break;
        }
      }
      if (payload == null) {
        showAppToast(context, '启动后进入的房间已不在收藏中');
        return;
      }
    } else {
      // 旧配置未指定收藏房间：回退到上次所在房间。
      payload = getIt<AppSettingsService>().getLastRoomPayload();
    }
    if (payload == null) return;

    try {
      await getIt<ConnectionService>().joinWithPayload(payload);
      if (!mounted) return;
      showAppToast(context, '已自动进入房间');
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '自动进入房间失败：${errorText(e)}');
    }
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
    if (_bookmarkSearchOpen) _closeBookmarkSearch();
    setState(() => _selectedIndex = index);
    if (index == _settingsTabIndex) _refreshFirewallStatus();
  }

  /// 展开手机端底部搜索胶囊；离开收藏页或收起时清空搜索词。
  void _openBookmarkSearch() {
    if (_bookmarkSearchOpen) return;
    setState(() => _bookmarkSearchOpen = true);
  }

  void _closeBookmarkSearch() {
    getIt<BookmarkSearchState>().clear();
    if (!_bookmarkSearchOpen) return;
    setState(() => _bookmarkSearchOpen = false);
  }

  /// 进入设置页时同步防火墙真实状态，避免 IndexedStack 缓存导致开关过期。
  void _refreshFirewallStatus() {
    if (RuntimePlatform.isWindows) {
      unawaited(getIt<FirewallService>().refreshAllProfiles());
    }
  }

  /// 悬浮底栏右侧的行动胶囊：收藏页放搜索，服务器页放刷新与添加。
  ///
  /// 读取 signals，必须在 [Watch] 内调用。
  List<BottomNavAction> _trailingActions(BuildContext context) {
    if (_selectedIndex == _bookmarksTabIndex) {
      // 搜索胶囊展开时收起圆钮，让导航恢复完整宽度。
      if (_bookmarkSearchOpen) return const [];
      return [
        BottomNavAction(
          icon: Icons.search_rounded,
          tooltip: '搜索收藏',
          onPressed: _openBookmarkSearch,
        ),
      ];
    }
    if (_selectedIndex == _serversTabIndex) {
      final servers = getIt<ServerState>().servers.value;
      // 空态已有「添加服务器」CTA，不重复提供入口。
      if (servers.isEmpty) return const [];
      final probing =
          getIt<ServerStatusState>().probingServerIds.value.isNotEmpty;
      return [
        BottomNavAction(
          icon: Icons.refresh_rounded,
          tooltip: probing ? '正在检测' : '重新检测并测速',
          loading: probing,
          onPressed: probing ? null : () => unawaited(probeAllServers(context)),
        ),
        BottomNavAction(
          icon: Icons.add_rounded,
          tooltip: '添加服务器',
          onPressed: () => showAddServerDialog(context),
        ),
      ];
    }
    return const [];
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

    // 手机没有模拟顶栏，由内容自己避开状态栏；桌面窄窗口仍有标题栏。
    return SafeArea(top: !_isDesktop, bottom: false, child: stack);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < AppBreakpoints.narrow;
    _screenStateService.updateScreenWidth(screenWidth);
    // 手机端：收藏页才在悬浮底栏右侧留搜索位。
    final showBookmarkSearch =
        isCompact && _selectedIndex == _bookmarksTabIndex;
    final searchOpen = showBookmarkSearch && _bookmarkSearchOpen;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    // 没有键盘时搜索胶囊停在底栏上方：底栏贴底留白 + 胶囊自身高度（含内部留白）。
    final navTopOffset =
        AppDimensions.navBottomGap(context) +
        AppDimensions.navBarPadding * 2 +
        AppDimensions.navBarHeight;
    final nodes = getIt<NodeManagementService>();

    // 手机端去掉模拟顶栏，内容通栏铺到状态栏下方（Apple 页面规范）。
    final contentRadius = isCompact
        ? BorderRadius.zero
        : const BorderRadius.only(
            topLeft: Radius.circular(AppDimensions.radiusMd),
          );

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: palette.canvas,
        // 悬浮胶囊：内容一直延伸到底部、从胶囊下方透出，不再有“内容区底边”。
        extendBody: isCompact,
        body: Stack(
          children: [
            Row(
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
                        // 平板保留模拟顶栏；手机按 Apple 页面规范不显示，标题与操作交给页内。
                        else if (!isCompact)
                          Watch((context) {
                            return MobileChromeBar(
                              avatar: nodes.currentUserAvatar.value,
                              username: nodes.currentUsername.value,
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
            // 搜索胶囊单独浮在 body 里：键盘弹起时 Scaffold 会把 body 压到键盘顶部，
            // 贴住 body 底部就等于跟着键盘上移；胶囊底栏留在原位不动（被键盘遮住）。
            if (searchOpen)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: keyboardInset > 0 ? 0 : navTopOffset,
                child: BookmarkSearchBar(
                  key: const ValueKey('bookmark_search_bar'),
                  onClose: _closeBookmarkSearch,
                ),
              ),
          ],
        ),
        // 不加底色，让胶囊外的区域直接透出下面的内容。
        bottomNavigationBar: isCompact
            ? Padding(
                // 只让出少量底部留白，避免胶囊被过高的系统安全区顶得太远。
                padding: EdgeInsets.only(
                  bottom: AppDimensions.navBottomGap(context),
                ),
                // 行动胶囊依赖服务器列表与探测状态，放在 Watch 里响应式更新。
                child: Watch((navContext) {
                  return BottomNav(
                    key: const ValueKey('bottom_nav'),
                    navigationItems: _navigationItems,
                    selectedIndex: _selectedIndex,
                    onSelected: _handleDestinationSelected,
                    trailingActions: _trailingActions(navContext),
                  );
                }),
              )
            : null,
      ),
    );
  }
}
