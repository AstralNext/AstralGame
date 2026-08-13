import 'dart:async';

import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/connection_service.dart';
import 'package:astral_game/data/services/connectivity_status_service.dart';
import 'package:astral_game/data/services/firewall_service.dart';
import 'package:astral_game/data/services/hitokoto_service.dart';
import 'package:astral_game/data/services/join_link_service.dart';
import 'package:astral_game/data/services/alcy_wallpaper_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/peer_rpc/methods/game_methods.dart';
import 'package:astral_game/data/services/peer_rpc/methods/message_methods.dart';
import 'package:astral_game/data/services/peer_rpc/methods/node_methods.dart';
import 'package:astral_game/data/services/peer_rpc/methods/user_methods.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_client.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_router.dart';
import 'package:astral_game/data/services/p2p_config_service.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/open_games_service.dart';
import 'package:astral_game/data/services/room_assist_service.dart';
import 'package:astral_game/data/services/room_persistence_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/services/shell_navigation_service.dart';
import 'package:astral_game/data/services/server_persistence_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
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
import 'package:astral_rust_core/p2p_service.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

final getIt = GetIt.instance;

/// 设置依赖注入
Future<void> setupDI() async {
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  final appLog = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.none,
    ),
  );
  getIt.registerSingleton<Logger>(appLog);
  getIt.registerSingleton<AppSettingsService>(AppSettingsService(prefs));

  getIt.registerSingleton<ScreenStateService>(ScreenStateService());
  getIt.registerSingleton<ShellNavigationService>(ShellNavigationService());

  getIt.registerLazySingleton<P2PService>(() => P2PService());
  await getIt<P2PService>().ensureInitialized();
  await ClientRuntimeInfo.warmUp();

  getIt.registerSingleton<ConnectivityStatusService>(ConnectivityStatusService());
  unawaited(getIt<ConnectivityStatusService>().start());

  getIt.registerLazySingleton<NodeManagementService>(
    () => NodeManagementService(),
  );
  getIt.registerSingleton<VpnState>(VpnState());
  getIt<VpnState>().setCustomRoutes(
    getIt<AppSettingsService>().getCustomVpnRoutes(),
  );

  getIt.registerSingleton<PeerRpcRouter>(PeerRpcRouter(getIt<P2PService>()));
  getIt.registerSingleton<PeerRpcClient>(PeerRpcClient(getIt<P2PService>()));

  getIt.registerLazySingleton<P2PConfigService>(
    () => P2PConfigService(
      getIt<AppSettingsService>(),
      getIt<ServerState>(),
    ),
  );

  getIt.registerLazySingleton<ShareCodeService>(() => ShareCodeService());
  getIt.registerLazySingleton<JoinLinkService>(() => JoinLinkService());
  getIt.registerLazySingleton<GameAssistRulesService>(
    () => GameAssistRulesService(),
  );
  getIt.registerLazySingleton<RoomAssistService>(
    () => RoomAssistService(
      getIt<P2PService>(),
      getIt<GameAssistRulesService>(),
    ),
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
  // 不阻塞启动：本地 asset 先填目录，远程 gamerules 后台拉取。
  unawaited(getIt<GameAssistRulesService>().ensureLoaded());
  getIt.registerLazySingleton<HitokotoService>(() => HitokotoService());
  getIt.registerLazySingleton<AlcyWallpaperService>(() => AlcyWallpaperService());

  getIt.registerLazySingleton<ServerState>(() => ServerState());
  getIt.registerLazySingleton<ServerStatusState>(() => ServerStatusState());
  getIt.registerLazySingleton<ServerPersistenceService>(
    () => ServerPersistenceService(),
  );

  getIt.registerLazySingleton<SettingsState>(() => SettingsState());
  getIt<SettingsState>().loadFromPersistence();
  getIt.registerLazySingleton<ThemeRevealController>(() => ThemeRevealController());

  getIt.registerLazySingleton<RoomState>(() => RoomState());

  final serverState = getIt<ServerState>();
  final serverPersistence = getIt<ServerPersistenceService>();
  serverState.setPersistenceCallbacks(
    loadCallback: serverPersistence.loadServers,
    saveCallback: serverPersistence.saveServers,
  );
  await serverState.loadFromPersistence();

  getIt.registerLazySingleton<RoomPersistenceService>(
    () => RoomPersistenceService(prefs),
  );

  final roomState = getIt<RoomState>();
  roomState.initPersistence(getIt<RoomPersistenceService>());
  await roomState.loadFromPersistence();
  roomState.restoreSelectedRoom(
    getIt<RoomPersistenceService>().loadSelectedRoomId(),
  );

  getIt.registerLazySingleton<ConnectionService>(
    () => ConnectionService(
      getIt<P2PService>(),
      getIt<P2PConfigService>(),
      getIt<NodeManagementService>(),
      getIt<RoomState>(),
      getIt<VpnManager>(),
      getIt<ShareCodeService>(),
      getIt<RoomAssistService>(),
      getIt<GameAssistRulesService>(),
      getIt<AppSettingsService>(),
      getIt<OpenGamesService>(),
    ),
  );

  getIt.registerLazySingleton<FirewallService>(() => FirewallService());
  unawaited(getIt<FirewallService>().refreshPrivateProfile());

  getIt.registerSingleton<UpdateState>(UpdateState());
  getIt.registerLazySingleton<UpdateService>(
    () => UpdateService(getIt<UpdateState>()),
  );

  getIt.registerLazySingleton<VpnManager>(
    () => VpnManager(getIt<VpnState>(), getIt<P2PService>()),
  );

  await _initPeerRpcRouter();
}

/// 释放所有服务资源
void disposeDI() {
  if (getIt.isRegistered<JoinLinkService>()) {
    getIt<JoinLinkService>().dispose();
  }
  if (getIt.isRegistered<ConnectivityStatusService>()) {
    unawaited(getIt<ConnectivityStatusService>().dispose());
  }
  getIt<NodeManagementService>().dispose();
  getIt<ScreenStateService>().dispose();
  getIt<ServerStatusState>().dispose();
  getIt<PeerRpcClient>().dispose();
  getIt<PeerRpcRouter>().stop();
}

/// 注册 peer-RPC 路由器的方法集合。真正绑定到 EasyTier instance 的动作发生在
/// [`ConnectionService.connectToRoom`] 成功后；这里只完成「注册一次，多次连接复用」
/// 的 handler 装载。
Future<void> _initPeerRpcRouter() async {
  final router = getIt<PeerRpcRouter>();
  final appSettings = getIt<AppSettingsService>();
  final nodeManagement = getIt<NodeManagementService>();

  router.registerAll(UserMethods(appSettings).methods);
  router.registerAll(NodeMethods(nodeManagement).methods);
  router.registerAll(MessageMethods().methods);
  router.registerAll(GameMethods().methods);

  appLogger.d(
    '[PeerRpc] router ready (not yet bound), methods=${router.methodsCount}',
  );
}
