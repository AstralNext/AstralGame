import 'dart:async';
import 'dart:io';

import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/data/services/isp_info_service.dart';
import 'package:astral_game/data/services/firewall_service.dart';
import 'package:astral_game/data/services/hitokoto_service.dart';
import 'package:astral_game/data/services/join_link_service.dart';
import 'package:astral_game/data/services/linux_capability_service.dart';
import 'package:astral_game/data/services/alcy_wallpaper_service.dart';
import 'package:astral_game/data/services/network_optimize_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/peer_rpc/methods/game_methods.dart';
import 'package:astral_game/data/services/peer_rpc/methods/message_methods.dart';
import 'package:astral_game/data/services/peer_rpc/methods/node_methods.dart';
import 'package:astral_game/data/services/peer_rpc/methods/user_methods.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_client.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_router.dart';
import 'package:astral_game/data/services/p2p_config_service.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/game_inject_service.dart';
import 'package:astral_game/data/services/open_games_service.dart';
import 'package:astral_game/data/services/room_assist_service.dart';
import 'package:astral_game/data/services/windows_process_watch.dart';
import 'package:astral_game/data/services/windows_time_sync_service.dart';
import 'package:astral_game/data/services/bookmark_store.dart';
import 'package:astral_game/data/services/bookmark_cover_store.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/data/services/smart_dns_config_updater.dart';
import 'package:astral_game/data/services/server_persistence_service.dart';
import 'package:astral_game/data/services/shortcut_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:astral_game/data/state/bookmark_search_state.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/state/server_state.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/data/state/theme_reveal_state.dart';
import 'package:astral_game/data/state/update_state.dart';
import 'package:astral_game/data/services/update_service.dart';
import 'package:astral_game/data/services/vpn_manager.dart';
import 'package:astral_game/data/state/vpn_state.dart';
import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/ping_util.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:astral_game/src/rust/api/p2p.dart' show subscribeCoreLogs;
import 'package:astral_game/src/rust/frb_generated.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final getIt = GetIt.instance;

/// 注册在 [disposeDI] 中需要调用的清理回调。按注册逆序执行。
final List<FutureOr<void> Function()> _disposeCallbacks = [];

/// 注册一个服务的清理回调，在 [disposeDI] 时统一执行。
///
/// 使用方式：在 [setupDI] 中 `getIt.registerX<Foo>(...)` 之后立即调用：
/// ```dart
/// _registerDispose<Foo>((s) => s.dispose());
/// _registerDispose<Foo>((s) => s.stop(), async: true);
/// ```
///
/// 这样新增服务不需要再同时改 [setupDI] 和 [disposeDI] 两处。
void _registerDispose<T extends Object>(
  FutureOr<void> Function(T service) cleanup, {
  bool async = false,
}) {
  _disposeCallbacks.add(() {
    if (!getIt.isRegistered<T>()) return null;
    final service = getIt<T>();
    return async ? Future.microtask(() => cleanup(service)) : cleanup(service);
  });
}

/// 设置依赖注入
Future<void> setupDI() async {
  // 为了保证 dispose 顺序（先创建的后销毁），每次 setupDI 前清空列表。
  _disposeCallbacks.clear();

  // 启动期这几项互不依赖（prefs / 支持目录 / Rust 动态库 / 本机环境 / 收藏库），
  // 先一起发起再按需 await，避免串行叠加成"启动要等几秒"。
  final prefsFuture = SharedPreferences.getInstance();
  final supportDirFuture = getApplicationSupportDirectory();
  final rustInitFuture = RustLib.init();
  final runtimeInfoFuture = ClientRuntimeInfo.warmUp();
  final bookmarkStoreFuture = supportDirFuture.then(
    (dir) => IsarBookmarkStore.open(p.join(dir.path, 'db')),
  );

  final prefs = await prefsFuture;
  getIt.registerSingleton<SharedPreferences>(prefs);

  final appLog = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      printEmojis: false,
    ),
  );
  setAppLogger(appLog);
  final supportDir = await supportDirFuture;
  final settings = AppSettingsService(prefs, supportDir: supportDir);
  await settings.warmUpAvatar();
  getIt.registerSingleton<AppSettingsService>(settings);

  getIt.registerSingleton<ScreenStateService>(ScreenStateService());
  _registerDispose<ScreenStateService>((s) => s.dispose());
  getIt.registerSingleton<ShellNavigationService>(ShellNavigationService());
  getIt.registerSingleton<ShortcutService>(const ShortcutService());

  // 初始化 FRB：加载 Rust 动态库并运行 #[frb(init)] 引导（启动共享 P2P runtime）。
  await rustInitFuture;
  await runtimeInfoFuture;

  getIt.registerSingleton<ConnectivityStatusService>(
    ConnectivityStatusService(),
  );
  _registerDispose<ConnectivityStatusService>((s) => s.dispose(), async: true);
  unawaited(getIt<ConnectivityStatusService>().start());

  getIt.registerSingleton<IspInfoService>(
    IspInfoService(getIt<ConnectivityStatusService>()),
  );
  _registerDispose<IspInfoService>((s) => s.dispose(), async: true);
  getIt<IspInfoService>().start();

  getIt.registerLazySingleton<FirewallService>(() => FirewallService());
  unawaited(getIt<FirewallService>().refreshPrivateProfile());
  getIt.registerLazySingleton<NetworkOptimizeService>(
    () => NetworkOptimizeService(),
  );
  getIt.registerLazySingleton<SmartDnsConfigUpdater>(
    () => SmartDnsConfigUpdater(
      networkOptimize: getIt<NetworkOptimizeService>(),
      cacheDir: Directory(p.join(supportDir.path, 'dns')),
    ),
  );
  _registerDispose<SmartDnsConfigUpdater>((s) => s.close());
  if (RuntimePlatform.isWindows) {
    unawaited(getIt<NetworkOptimizeService>().refresh());
    // 网络加速已启用时，顺带把远端 smartdns.conf 同步下来（失败保留本地配置）。
    unawaited(getIt<SmartDnsConfigUpdater>().checkAndApply());
    unawaited(ensureWindowsAliyunNtp());
  }

  getIt.registerSingleton<PeerRpcRouter>(PeerRpcRouter());
  _registerDispose<PeerRpcRouter>((s) => s.stop());
  getIt.registerSingleton<PeerRpcClient>(PeerRpcClient());
  _registerDispose<PeerRpcClient>((s) => s.dispose());

  getIt.registerLazySingleton<NodeManagementService>(
    () => NodeManagementService(
      appSettings: getIt<AppSettingsService>(),
      peerRpc: getIt<PeerRpcClient>(),
      connectivity: getIt<ConnectivityStatusService>(),
      firewall: getIt<FirewallService>(),
      ispInfo: getIt<IspInfoService>(),
    ),
  );
  _registerDispose<NodeManagementService>((s) => s.dispose());
  getIt.registerSingleton<VpnState>(VpnState());
  getIt<VpnState>().setCustomRoutes(
    getIt<AppSettingsService>().getCustomVpnRoutes(),
  );

  getIt.registerLazySingleton<ShareCodeService>(() => ShareCodeService());
  _registerDispose<ShareCodeService>((s) => s.close());
  getIt.registerLazySingleton<JoinLinkService>(() => JoinLinkService());
  _registerDispose<JoinLinkService>((s) => s.dispose());
  getIt.registerLazySingleton<GameAssistRulesService>(
    () => GameAssistRulesService(
      cacheDir: Directory(p.join(supportDir.path, 'gamerules_cache')),
    ),
  );
  _registerDispose<GameAssistRulesService>((s) => s.close());
  getIt.registerLazySingleton<WindowsProcessWatch>(() => WindowsProcessWatch());
  _registerDispose<WindowsProcessWatch>((s) => s.dispose());
  getIt.registerLazySingleton<RoomAssistService>(
    () => RoomAssistService(
      getIt<GameAssistRulesService>(),
      getIt<WindowsProcessWatch>(),
    ),
  );
  _registerDispose<RoomAssistService>((s) => s.stopAll(), async: true);
  getIt.registerLazySingleton<GameInjectService>(
    () => GameInjectService(
      getIt<GameAssistRulesService>(),
      getIt<WindowsProcessWatch>(),
    ),
  );
  _registerDispose<GameInjectService>((s) => s.stop(), async: true);
  // 不阻塞启动：本地 asset → 测试目录 gamerules/ → 远程。
  unawaited(getIt<GameAssistRulesService>().ensureLoaded());
  getIt.registerLazySingleton<HitokotoService>(() => HitokotoService());
  _registerDispose<HitokotoService>((s) => s.close());
  getIt.registerLazySingleton<AlcyWallpaperService>(
    () => AlcyWallpaperService(),
  );
  _registerDispose<AlcyWallpaperService>((s) => s.close());

  getIt.registerLazySingleton<ServerState>(() => ServerState());
  getIt.registerLazySingleton<ServerStatusState>(() => ServerStatusState());
  _registerDispose<ServerStatusState>((s) => s.dispose());
  getIt.registerLazySingleton<ServerPersistenceService>(
    () => ServerPersistenceService(),
  );

  final serverState = getIt<ServerState>();
  final serverPersistence = getIt<ServerPersistenceService>();
  serverState.setPersistenceCallbacks(
    loadCallback: serverPersistence.loadServers,
    saveCallback: serverPersistence.saveServers,
  );
  await serverState.loadFromPersistence();

  getIt.registerLazySingleton<P2PConfigService>(
    () => P2PConfigService(getIt<AppSettingsService>(), getIt<ServerState>()),
  );
  getIt.registerLazySingleton<OpenGamesService>(
    () => OpenGamesService(
      getIt<GameAssistRulesService>(),
      getIt<NodeManagementService>(),
      getIt<PeerRpcClient>(),
      getIt<PeerRpcRouter>(),
      getIt<AppSettingsService>(),
    ),
  );
  _registerDispose<OpenGamesService>((s) => s.stop(), async: true);

  getIt.registerLazySingleton<SettingsState>(
    () => SettingsState(getIt<AppSettingsService>()),
  );
  getIt<SettingsState>().loadFromPersistence();
  getIt.registerLazySingleton<ThemeRevealController>(
    () => ThemeRevealController(getIt<SettingsState>()),
  );

  getIt.registerLazySingleton<RoomState>(() => RoomState());

  getIt.registerLazySingleton<BookmarkSearchState>(() => BookmarkSearchState());

  // 收藏持久化：Isar（打开时顺带一次性导入旧版 bookmarks.json）。
  final bookmarkStore = await bookmarkStoreFuture;
  getIt.registerSingleton<BookmarkStore>(bookmarkStore);

  // 收藏自定义封面：图片落盘在支持目录，不占 Isar 空间。
  getIt.registerLazySingleton<BookmarkCoverStore>(
    () => BookmarkCoverStore(
      directory: Directory(p.join(supportDir.path, 'covers')),
    ),
  );

  final roomState = getIt<RoomState>();
  roomState.initPersistence(bookmarkStore);
  await roomState.loadFromPersistence();

  getIt.registerLazySingleton<VpnManager>(() => VpnManager(getIt<VpnState>()));
  _registerDispose<VpnManager>((s) => s.dispose());
  // Linux 桌面：tun 需要 CAP_NET_ADMIN，这里负责检测与一键授权。
  getIt.registerLazySingleton<LinuxCapabilityService>(
    LinuxCapabilityService.new,
  );
  getIt.registerLazySingleton<ConnectionService>(
    () => ConnectionService(
      getIt<P2PConfigService>(),
      getIt<NodeManagementService>(),
      getIt<RoomState>(),
      getIt<VpnManager>(),
      getIt<ShareCodeService>(),
      getIt<RoomAssistService>(),
      getIt<GameInjectService>(),
      getIt<GameAssistRulesService>(),
      getIt<AppSettingsService>(),
      getIt<OpenGamesService>(),
      getIt<PeerRpcClient>(),
      getIt<PeerRpcRouter>(),
    ),
  );
  _registerDispose<ConnectionService>((s) => s.disconnect(), async: true);

  getIt.registerSingleton<UpdateState>(UpdateState());
  getIt.registerLazySingleton<UpdateService>(
    () => UpdateService(getIt<UpdateState>()),
  );

  await _initPeerRpcRouter();
  _initEasyTierCoreLogs();
}

/// 订阅 EasyTier 内核事件流并打到应用日志。
///
/// tun device error / dhcp ip changed / dhcp ipv6 changed 这类关键信息只在
/// `subscribe_core_logs` 上给出；此前没有任何地方订阅，虚拟网卡起不来时
/// 日志里只剩「已连接 Ns 仍无虚拟 IP」这种结果，看不到原因。
void _initEasyTierCoreLogs() {
  final subscription = subscribeCoreLogs().listen((event) {
    final message = event.message.trim();
    if (message.isEmpty) return;
    appLogger.i('[EasyTier] $message');
  }, onError: (Object e) => appLogger.w('[EasyTier] 内核日志流异常: $e'));
  _disposeCallbacks.add(() {
    unawaited(subscription.cancel());
  });
}

/// 释放所有服务资源（按注册逆序执行清理回调）。
void disposeDI() {
  // 逆序执行：最后注册的最先 dispose，避免依赖项被提前销毁。
  for (int i = _disposeCallbacks.length - 1; i >= 0; i--) {
    try {
      final result = _disposeCallbacks[i].call();
      if (result is Future) {
        unawaited(result);
      }
    } catch (e) {
      appLogger.w('[DI] dispose 回调 #$i 执行异常: $e');
    }
  }
  _disposeCallbacks.clear();
  unawaited(PingUtil.close());
}

/// 注册 peer-RPC 路由器的方法集合。真正绑定到 EasyTier instance 的动作发生在
/// [`ConnectionService.connectToRoom`] 成功后；这里只完成「注册一次，多次连接复用」
/// 的 handler 装载。
Future<void> _initPeerRpcRouter() async {
  final router = getIt<PeerRpcRouter>();
  final appSettings = getIt<AppSettingsService>();
  final nodeManagement = getIt<NodeManagementService>();

  router.registerAll(
    UserMethods(
      appSettings,
      connectivity: getIt<ConnectivityStatusService>(),
      firewall: getIt<FirewallService>(),
      ispInfo: getIt<IspInfoService>(),
    ).methods,
  );
  router.registerAll(NodeMethods(nodeManagement).methods);
  router.registerAll(MessageMethods().methods);
  router.registerAll(GameMethods(getIt<OpenGamesService>()).methods);

  appLogger.d(
    '[PeerRpc] router ready (not yet bound), methods=${router.methodsCount}',
  );
}
