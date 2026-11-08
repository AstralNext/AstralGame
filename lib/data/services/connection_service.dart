import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/models/transport_mode.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/easytier_core_event_bus.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/game_inject_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/open_games_service.dart';
import 'package:astral_game/data/services/p2p_config_service.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_client.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_router.dart';
import 'package:astral_game/data/services/room_assist_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:astral_game/data/services/steam_transport_service.dart';
import 'package:astral_game/data/services/vpn_manager.dart';
import 'package:astral_game/data/state/connection_phase.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:astral_game/src/rust/api/p2p.dart';
import 'package:signals/signals_core.dart';

/// 连接服务：建房 / 进房（6 位 32 进制短码或离线 Base64）/ 会话，不落盘房间历史。
///
/// 进网方式：双方共享随机 [network_name] + [network_secret]。
class ConnectionService {
  ConnectionService(
    this._p2pConfig,
    this._nodeManagement,
    this._roomState,
    this._vpnManager,
    this._shareCodes,
    this._roomAssist,
    this._gameInject,
    this._gameRules,
    this._appSettings,
    this._openGames,
    this._peerRpc,
    this._peerRpcRouter,
    this._coreEvents,
    this._settingsState,
  );

  final P2PConfigService _p2pConfig;
  final NodeManagementService _nodeManagement;
  final RoomState _roomState;
  final VpnManager _vpnManager;
  final ShareCodeService _shareCodes;
  final RoomAssistService _roomAssist;
  final GameInjectService _gameInject;
  final GameAssistRulesService _gameRules;
  final AppSettingsService _appSettings;
  final OpenGamesService _openGames;
  final PeerRpcClient _peerRpc;
  final PeerRpcRouter _peerRpcRouter;
  final EasyTierCoreEventBus _coreEvents;
  final SettingsState _settingsState;

  /// Steam 组网（SDR 虚拟局域网）传输实现；EasyTier 模式不启用。
  final SteamTransportService _steam = SteamTransportService();

  /// 当前设置是否要求走 Steam 组网。
  ///
  /// 以运行时的 [SettingsState.transportMode] 为准，不再回读本地存储：
  /// 自检启动（`--steam-selftest`）等场景只改内存模式、不落盘，读存储会
  /// 把 Steam 建房错当成 EasyTier，进而误报「请先启用服务器」。
  /// 平台与实验性开关仍统一由 [SettingsState.transportGate] 判定。
  bool get _steamModeActive =>
      _settingsState.transportMode.value == TransportMode.steam &&
      _settingsState.transportGate.isAvailable(TransportMode.steam);

  /// 预热 Steam 客户端与 SDR 中继。
  ///
  /// `SteamAPI_Init` 与 SDR 就绪通常要数秒；在切换模式 / 应用启动时先跑起来，
  /// 点「创建房间」时 `waitReady` 基本能立刻返回，不用在对话框关掉后干等。
  Future<void> prewarmSteamTransport() async {
    if (!_steamModeActive) return;
    try {
      await _steam.status();
    } catch (e) {
      appLogger.w('[ConnectionService] Steam 预热失败: $e');
    }
  }

  /// 桌面端虚拟网卡（Wintun / Linux tun）创建超时。
  ///
  /// 权限不足、驱动异常时 EasyTier 会卡在建网卡这一步，用户只看到「连接中」
  /// 没有任何提示，因此超过这个时间就判定失败并给出可操作的原因。
  static const Duration desktopTunTimeout = Duration(seconds: 30);

  /// 全平台：实例启动后等待与服务器建立连接的时间。
  static const Duration serverLinkTimeout = Duration(seconds: 20);

  /// 健康检查轮询间隔。
  static const Duration _healthCheckInterval = Duration(milliseconds: 200);

  static const String _desktopTunFailureMessage =
      '虚拟网卡（TUN）创建失败，无法建立联机网络。请检查网络权限后重试：'
      'Windows 请以管理员身份运行，Linux 请确认已授予网络能力。';

  /// 是否正在建立连接；由 [RoomState.connection] 派生，不再是独立状态。
  late final isConnecting = computed<bool>(
    () => _roomState.connection.phaseSignal.value == ConnectionPhase.linking,
  );

  /// 已有会话、传输仍在连接中（供房间卡「连接中」提示）。
  late final isLinking = computed<bool>(
    () =>
        _roomState.connection.phaseSignal.value == ConnectionPhase.linking &&
        _roomState.session.value != null,
  );

  /// 防重入标记：只约束 [_connect] 自身，不对外暴露。
  bool _connectInFlight = false;

  /// 一次用户级连接尝试是否已被认领（同步置位，跨 await 有效）。
  bool _attemptClaimed = false;

  /// 递增以作废进行中的乐观连接（例如用户在连接中点了离开）。
  final _link = ConnectionLinkEpoch();

  /// 检查当前连接 epoch 是否仍然有效（未被取消 / 新连接尚未开始）。
  ///
  /// 在 [`_connect`] 等长流程中每执行完一步异步操作后调用，
  /// 返回 false 说明用户在操作中取消了连接，流程应立刻回滚并返回。
  bool _isLinkActive(int epoch) => _link.isLive(epoch);

  /// 把底层 Rust / Platform 异常翻译成用户可读的错误。
  ///
  /// 当前仍通过字符串特征匹配做分类（Rust 侧返回的是错误消息字符串），
  /// 但集中在此处，便于后续换成结构化错误码后单点升级。
  Object _translateConnectionError(Object e) {
    if (!RuntimePlatform.isWindows) return e;
    final msg = e.toString().toLowerCase();
    const tunKeywords = {'tun', 'wintun', 'access is denied', 'privilege'};
    final hit = tunKeywords.any(msg.contains);
    if (hit) {
      return StateError('虚拟网卡启动失败，请以管理员身份重新运行 Astral Game');
    }
    return e;
  }

  /// 连接并启动房间辅助服务（create / join / resume 共用流程）。
  /// 抛出 [ConnectionAbortedException] 表示被取消；抛出 [StateError] 表示连接失败。
  Future<void> _connectAndStartServices({
    required String networkName,
    required String secret,
    List<PeerEndpoint>? peersOverride,
    required String purpose,
    required String gameId,
    required bool isHost,
    required int epoch,
    String failMessage = '连接失败，请重试',
  }) async {
    final ok = await _connect(
      networkName: networkName,
      secret: secret,
      peersOverride: peersOverride,
      purpose: purpose,
      gameId: gameId,
      epoch: epoch,
    );
    if (!_isLinkActive(epoch)) {
      throw const ConnectionAbortedException();
    }
    if (!ok) {
      throw StateError(failMessage);
    }
    await _roomAssist.startForRoom(isHost: isHost, gameId: gameId);
    await _gameInject.startForRoom(gameId: gameId);
    await _openGames.startForRoom(isHost: isHost, gameId: gameId);
  }

  EffectCleanup? _guestPresenceDispose;

  /// 客机侧「房间内无其他成员」日志的边沿标记。
  ///
  /// UI 已不再消费房主在线状态，这里只保留一次性告警，避免反复刷日志。
  bool _guestPresenceOffline = false;

  /// 最近一次离线邀请串（短码服务失败时的回退）。
  String? lastOfflineInvite;

  /// 本次尝试开始时是否已经处于 connected（用于失败后恢复旧连接）。
  bool _attemptStartedFromConnected = false;

  /// 认领一次连接尝试；linking / disconnecting 期间重复调用会被明确拒绝。
  void _beginConnectionAttempt() {
    final phase = _roomState.connection.phase;
    if (_attemptClaimed ||
        phase == ConnectionPhase.linking ||
        phase == ConnectionPhase.disconnecting) {
      throw const ConnectionBusyException();
    }
    _attemptClaimed = true;
    _attemptStartedFromConnected = phase == ConnectionPhase.connected;
    _roomState.connection.beginLinking();
  }

  /// 释放尝试；仍未进入 connected 的（失败/取消）按旧连接是否还在决定去向。
  void _endConnectionAttempt() {
    _attemptClaimed = false;
    final wasConnected = _attemptStartedFromConnected;
    _attemptStartedFromConnected = false;
    if (_roomState.connection.phase != ConnectionPhase.linking) return;
    // 在拆掉旧传输之前就失败（例如校验参数不通过）：旧连接仍然可用。
    if (wasConnected && _nodeManagement.isRunning) {
      _roomState.connection.markConnected();
    } else {
      _roomState.connection.reset();
    }
  }

  /// 创建房间：先发短码并写入会话（UI 立刻可见），再开 EasyTier。
  Future<ActiveRoomSession> createAndConnect({
    required String gameId,
    required String gameName,
    String? displayName,
    String gate = kSteamLobbyGateBasic,
    String? extraPassword,
  }) async {
    _beginConnectionAttempt();
    try {
      lastOfflineInvite = null;
      if (_steamModeActive) {
        return await _createSteamRoom(
          gameId: gameId,
          gameName: gameName,
          displayName: displayName,
          gate: gate,
          extraPassword: extraPassword,
        );
      }
      final hostPeers = _p2pConfig.enabledPeers();
      if (hostPeers.isEmpty) {
        throw StateError('请先在服务器列表中启用至少一个服务器，再创建房间');
      }
      final networkName = 'ag_${_randomId(10)}';
      final secret = _p2pConfig.generateRoomCode(length: 16);
      final label = (displayName == null || displayName.trim().isEmpty)
          ? gameName
          : displayName.trim();

      final payload = RoomInvitePayload(
        gameId: gameId,
        gameName: gameName,
        networkName: networkName,
        networkSecret: secret,
        peers: hostPeers,
        displayName: label,
      );
      lastOfflineInvite = encodeOfflineInvite(payload);

      String? shortCode;
      try {
        final created = await _shareCodes.createOrReuse(payload);
        shortCode = created.code;
      } catch (e) {
        appLogger.w('[ConnectionService] 短码服务不可用，改用离线邀请: $e');
      }

      final session = ActiveRoomSession(
        isHost: true,
        gameId: gameId,
        gameName: gameName,
        networkName: networkName,
        networkSecret: secret,
        displayName: label,
        shortCode: shortCode,
        peers: hostPeers,
      );
      _roomState.setSession(session);
      final epoch = _link.begin();

      var linked = false;
      try {
        await _connectAndStartServices(
          networkName: networkName,
          secret: secret,
          purpose: 'create',
          gameId: gameId,
          isHost: true,
          epoch: epoch,
        );
        linked = true;
        await _appSettings.setLastRoomPayload(payload);
        return session;
      } on ConnectionAbortedException {
        rethrow;
      } catch (e) {
        if (!linked && _isLinkActive(epoch)) {
          await disconnect();
        }
        rethrow;
      }
    } finally {
      _endConnectionAttempt();
    }
  }

  /// Steam 组网建房：wintun 虚拟网卡 + Steam SDR 星型局域网（房主转发）。
  Future<ActiveRoomSession> _createSteamRoom({
    required String gameId,
    required String gameName,
    String? displayName,
    String gate = kSteamLobbyGateBasic,
    String? extraPassword,
  }) async {
    final status = await _steam.waitReady();
    if (!SteamTransportService.isReady(status)) {
      throw StateError('${SteamTransportService.describeNotReady(status)}，请稍后重试。');
    }
    if (status.steamId.isEmpty) {
      throw StateError('未获取到 SteamID：请先启动并登录 Steam 客户端。');
    }

    final networkName = 'ag_${_randomId(10)}';
    final extra = extraPassword?.trim() ?? '';
    final secret = composeSteamJoinToken(extraPassword: extra);
    final effectiveGate = extra.isNotEmpty ? kSteamLobbyGateDouble : gate;
    final label = (displayName == null || displayName.trim().isEmpty)
        ? gameName
        : displayName.trim();

    try {
      await _steam.createLobby(
        gameId: gameId,
        name: label,
        gate: effectiveGate,
        maxMembers: 8,
        joinToken: secret,
        nickname: status.persona,
      );
      _peerRpc.bindSteam();
      await _peerRpcRouter.startSteam();
      _nodeManagement.startSteam();
    } catch (e) {
      await _unbindPeerRpc();
      _nodeManagement.stop();
      await _steam.stop();
      rethrow;
    }
    // 游戏辅助是增值能力，失败只记日志，不阻断组网。
    try {
      await _startGameAssist(gameId: gameId, isHost: true);
    } catch (e) {
      appLogger.w('[ConnectionService] Steam 辅助服务启动失败: $e');
    }

    final payload = RoomInvitePayload(
      gameId: gameId,
      gameName: gameName,
      networkName: networkName,
      networkSecret: secret,
      peers: const <PeerEndpoint>[],
      displayName: label,
      transport: 'steam',
      hostSteamId: status.steamId,
    );
    lastOfflineInvite = encodeOfflineInvite(payload);

    String? shortCode;
    try {
      final created = await _shareCodes.createOrReuse(payload);
      shortCode = created.code;
    } catch (e) {
      appLogger.w('[ConnectionService] Steam 房间短码不可用，改用离线邀请: $e');
    }

    final session = ActiveRoomSession(
      isHost: true,
      gameId: gameId,
      gameName: gameName,
      networkName: networkName,
      networkSecret: secret,
      displayName: label,
      shortCode: shortCode,
      peers: const <PeerEndpoint>[],
      transport: 'steam',
      hostSteamId: status.steamId,
    );
    _roomState.setSession(session);
    _roomState.setConnected(true, clearSession: false);
    await _appSettings.setLastRoomPayload(payload);
    appLogger.i(
      '[ConnectionService] Steam 组网房间已建立: $gameName vip=${status.virtualIp}',
    );
    return session;
  }

  /// Steam 组网加入：连到房主 SteamID，加入同一虚拟局域网。
  Future<ActiveRoomSession> _joinSteamRoom(
    RoomInvitePayload payload, {
    String? shortCode,
  }) async {
    final hostId = payload.hostSteamId?.trim() ?? '';
    if (hostId.isEmpty) {
      throw StateError('邀请缺少房主 SteamID，请让房主用新版重新分享。');
    }
    if (payload.networkSecret.isEmpty) {
      throw StateError('邀请缺少房间口令，请让房主重新分享。');
    }

    // 邀请里只需要房主 SteamID 与房间口令，虚拟 IP 由房主分配。
    final status = await _steam.waitReady();
    if (!SteamTransportService.isReady(status)) {
      throw StateError('${SteamTransportService.describeNotReady(status)}，请稍后重试。');
    }

    try {
      await _steam.startGuest(
        hostSteamId: hostId,
        joinToken: payload.networkSecret,
        nickname: status.persona,
        gameId: payload.gameId,
      );
      _peerRpc.bindSteam();
      await _peerRpcRouter.startSteam();
      _nodeManagement.startSteam();
    } catch (e) {
      await _unbindPeerRpc();
      _nodeManagement.stop();
      await _steam.stop();
      rethrow;
    }

    final session = ActiveRoomSession(
      isHost: false,
      gameId: payload.gameId,
      gameName: payload.gameName.isEmpty ? '房间' : payload.gameName,
      networkName: payload.networkName,
      networkSecret: payload.networkSecret,
      displayName: payload.displayName?.isNotEmpty == true
          ? payload.displayName!
          : (payload.gameName.isEmpty ? payload.networkName : payload.gameName),
      shortCode: shortCode,
      peers: payload.peers,
      transport: 'steam',
      hostSteamId: hostId,
    );
    _roomState.setSession(session);
    // 辅助服务失败不影响「传输可用」这一判断，不能反过来把连接判失败。
    try {
      await _startGameAssist(gameId: payload.gameId, isHost: false);
    } catch (e) {
      appLogger.w('[ConnectionService] Steam 辅助服务启动失败: $e');
    }
    _roomState.setConnected(true, clearSession: false);
    _armGuestPresenceWatch();
    appLogger.i(
      '[ConnectionService] 已加入 Steam 组网房间: host=$hostId '
      'vip=${status.virtualIp}',
    );
    return session;
  }

  /// 供 UI 直接使用大厅能力（搜索 / 邀请界面 / 待处理邀请）。
  SteamTransportService get steamTransport => _steam;

  /// 当前是否处于 Steam 组网模式（大厅搜房入口只在此时显示）。
  bool get steamModeActive => _steamModeActive;

  /// 从大厅搜索结果直接进房。
  ///
  /// 与邀请进房的区别：口令由「全工具基础口令 + 用户输入的可选额外密码」
  /// 拼成，房主与客人无需交换任何离线邀请串。
  Future<ActiveRoomSession> joinSteamLobby({
    required String lobbyId,
    required String gameId,
    required String gameName,
    String? extraPassword,
    String? displayName,
  }) async {
    _beginConnectionAttempt();
    try {
      final reason = _settingsState.transportGate.unavailableReason(
        TransportMode.steam,
      );
      if (reason != null) throw StateError('$reason，无法加入该房间。');
      final status = await _steam.waitReady();
      if (!SteamTransportService.isReady(status)) {
        throw StateError('${SteamTransportService.describeNotReady(status)}，请稍后重试。');
      }
      final token = composeSteamJoinToken(extraPassword: extraPassword);
      final info = await _steam.joinLobby(
        lobbyId: lobbyId,
        gameId: gameId,
        joinToken: token,
        nickname: status.persona,
      );
      try {
        _peerRpc.bindSteam();
        await _peerRpcRouter.startSteam();
        _nodeManagement.startSteam();
      } catch (e) {
        await _unbindPeerRpc();
        _nodeManagement.stop();
        await _steam.leaveLobby();
        rethrow;
      }
      final label = (displayName == null || displayName.trim().isEmpty)
          ? (gameName.isEmpty ? '房间' : gameName)
          : displayName.trim();
      final resolvedGameId = info.gameId.isEmpty ? gameId : info.gameId;
      final payload = RoomInvitePayload(
        gameId: resolvedGameId,
        gameName: gameName,
        networkName: 'ag_${info.lobbyId}',
        networkSecret: token,
        peers: const <PeerEndpoint>[],
        displayName: label,
        transport: 'steam',
        hostSteamId: info.hostSteamId,
      );
      final session = ActiveRoomSession(
        isHost: false,
        gameId: resolvedGameId,
        gameName: gameName.isEmpty ? '房间' : gameName,
        networkName: payload.networkName,
        networkSecret: token,
        displayName: label,
        peers: const <PeerEndpoint>[],
        transport: 'steam',
        hostSteamId: info.hostSteamId,
      );
      _roomState.setSession(session);
      try {
        await _startGameAssist(gameId: resolvedGameId, isHost: false);
      } catch (e) {
        appLogger.w('[ConnectionService] Steam 辅助服务启动失败: $e');
      }
      _roomState.setConnected(true, clearSession: false);
      _armGuestPresenceWatch();
      await _appSettings.setLastRoomPayload(payload);
      appLogger.i(
        '[ConnectionService] 已通过大厅加入 Steam 房间: '
        'lobby=$lobbyId host=${info.hostSteamId}',
      );
      return session;
    } finally {
      _endConnectionAttempt();
    }
  }

  /// 解析邀请输入（短码/离线）并返回完整 payload，**不真正加入房间**。
  /// 用于「解析并收藏」等场景。
  Future<({RoomInvitePayload payload, String? shortCode, String? offlineToken})>
  resolveInvitePayload(String raw) async {
    final token = requireJoinInviteToken(raw);
    if (looksLikeShortCode(token)) {
      final normalized = normalizeShareCode(token);
      final payload = await _shareCodes.fetch(normalized);
      return (payload: payload, shortCode: normalized, offlineToken: null);
    }
    final payload = decodeOfflineInvite(token);
    return (payload: payload, shortCode: null, offlineToken: token);
  }

  Future<ActiveRoomSession> joinWithInviteInput(String raw) async {
    _beginConnectionAttempt();
    try {
      final resolved = await resolveInvitePayload(raw);
      return await _joinWithPayload(
        resolved.payload,
        shortCode: resolved.shortCode,
      );
    } finally {
      _endConnectionAttempt();
    }
  }

  /// 当前应分享的一条 URL（短码优先，否则离线）。
  String? currentJoinShareUrl() {
    final session = _roomState.session.value;
    if (session == null || !session.isHost) return null;
    final url = buildJoinShareUrl(
      shortCode: session.shortCode,
      offlineInvite: currentOfflineInvite(),
    );
    return url.isEmpty ? null : url;
  }

  /// 为任意 [RoomInvitePayload] 取一条短码：同房间的有效码优先复用，过期才新建。
  ///
  /// 收藏页分享、成员侧临时分享都走这个入口。拿到码后**不会**自动写入 session，
  /// 调用方决定是否持久化（如 bookmark.lastShareCode）。
  Future<ShareCode> createShareCodeForPayload(RoomInvitePayload payload) {
    return _shareCodes.createOrReuse(payload);
  }

  /// 为当前会话取一条短码（房主/成员均可调）：有效码优先复用，过期才新建。
  Future<ShareCode> createShareCodeForCurrentSession() {
    final session = _roomState.session.value;
    if (session == null) {
      throw StateError('未连接房间，无法生成短码');
    }
    final payload = payloadFromCurrentSession();
    if (payload == null) {
      throw StateError('当前会话缺少配置，无法生成短码');
    }
    return _shareCodes.createOrReuse(payload);
  }

  /// 加入房间：6 位 32 进制短码。
  Future<ActiveRoomSession> joinWithShortCode(String code) async {
    _beginConnectionAttempt();
    try {
      final normalized = normalizeShareCode(code);
      final payload = await _shareCodes.fetch(normalized);
      return await _joinWithPayload(payload, shortCode: normalized);
    } finally {
      _endConnectionAttempt();
    }
  }

  /// 从任意 [RoomInvitePayload] 加入；收藏功能用它跳过短码服务。
  Future<ActiveRoomSession> joinWithPayload(
    RoomInvitePayload payload, {
    String? shortCode,
  }) async {
    _beginConnectionAttempt();
    try {
      return await _joinWithPayload(payload, shortCode: shortCode);
    } finally {
      _endConnectionAttempt();
    }
  }

  /// 依据当前会话生成一条完整 payload（用于「收藏当前房间」）。
  RoomInvitePayload? payloadFromCurrentSession() {
    final session = _roomState.session.value;
    if (session == null) return null;
    return RoomInvitePayload(
      gameId: session.gameId,
      gameName: session.gameName,
      networkName: session.networkName,
      networkSecret: session.networkSecret,
      peers: session.peers,
      displayName: session.displayName,
      transport: session.transport,
      hostSteamId: session.hostSteamId,
    );
  }

  Future<ActiveRoomSession> _joinWithPayload(
    RoomInvitePayload payload, {
    String? shortCode,
  }) async {
    if (payload.isSteamTransport) {
      // 邀请 / 收藏 / 启动自动进房都汇到这里：模式不可用时给出可读原因，
      // 不静默改走 EasyTier（Steam 房间没有 EasyTier 的 peer 信息，改了也进不去）。
      final reason = _settingsState.transportGate.unavailableReason(
        TransportMode.steam,
      );
      if (reason != null) throw StateError('$reason，无法加入该房间。');
      return _joinSteamRoom(payload, shortCode: shortCode);
    }
    final invitePeers = joinableInvitePeers(payload);

    final session = ActiveRoomSession(
      isHost: false,
      gameId: payload.gameId,
      gameName: payload.gameName.isEmpty ? '房间' : payload.gameName,
      networkName: payload.networkName,
      networkSecret: payload.networkSecret,
      displayName: payload.displayName?.isNotEmpty == true
          ? payload.displayName!
          : (payload.gameName.isEmpty ? payload.networkName : payload.gameName),
      shortCode: shortCode,
      peers: invitePeers,
    );
    _roomState.setSession(session);
    final epoch = _link.begin();

    // 加入即续期：后台向短码服务登记本房间（服务端按房间指纹复用同一码并
    // 滑动续期，顺带拿回管理令牌用于心跳），不阻塞进房。
    unawaited(_attachShareCode(payload, epoch));

    var linked = false;
    try {
      await _connectAndStartServices(
        networkName: payload.networkName,
        secret: payload.networkSecret,
        peersOverride: invitePeers,
        purpose: 'join',
        gameId: session.gameId,
        isHost: false,
        epoch: epoch,
      );
      linked = true;
      await _appSettings.setLastRoomPayload(payload);
      return session;
    } on ConnectionAbortedException {
      rethrow;
    } catch (e) {
      if (!linked && _isLinkActive(epoch)) {
        await disconnect();
      }
      rethrow;
    }
  }

  /// 客人侧短码登记：加入即续期，并缓存分享码，失败静默。
  ///
  /// 短码服务慢/不可用时不影响进房；同房间已有有效码会直接复用。
  Future<void> _attachShareCode(RoomInvitePayload payload, int epoch) async {
    try {
      final created = await _shareCodes.createOrReuse(payload);
      if (!_isLinkActive(epoch)) return;
      final current = _roomState.session.value;
      if (current == null || current.networkName != payload.networkName) return;
      _roomState.setSession(current.copyWith(shortCode: created.code));
    } catch (e) {
      appLogger.w('[ConnectionService] 自动创建短码失败: $e');
    }
  }

  /// 导出当前离线邀请（优先缓存；否则用会话重建）。
  String? currentOfflineInvite() {
    final cached = lastOfflineInvite?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    final session = _roomState.session.value;
    if (session == null || !session.isHost) return null;
    if (session.networkSecret.isEmpty) return null;
    final isTunnel = session.isSteamTransport;
    // Steam 组网没有服务器列表，进房只靠房主连接信息。
    final hostPeers = isTunnel
        ? const <PeerEndpoint>[]
        : _p2pConfig.enabledPeers();
    if (!isTunnel && hostPeers.isEmpty) return null;
    final payload = RoomInvitePayload(
      gameId: session.gameId,
      gameName: session.gameName,
      networkName: session.networkName,
      networkSecret: session.networkSecret,
      peers: hostPeers,
      displayName: session.displayName,
      transport: session.transport,
      hostSteamId: session.hostSteamId,
    );
    return encodeOfflineInvite(payload);
  }

  /// 离开房间：只关实例，不作废短码。
  ///
  /// 短码是房间级资源、靠存续期内的活动（加入 / 心跳）滑动续期，
  /// 不做「谁离开就删码」的主动作废——否则房主一退出，房间里其他人
  /// 手上的邀请链接立刻失效。
  Future<void> leaveRoom() async {
    // 用户主动离开：不再作为下次启动的「上次房间」。
    await _appSettings.setLastRoomPayload(null);
    await disconnect();
  }

  Future<bool> _connect({
    required String networkName,
    required String secret,
    List<PeerEndpoint>? peersOverride,
    String purpose = 'connect',
    String? gameId,
    required int epoch,
  }) async {
    if (_connectInFlight) {
      appLogger.w('[ConnectionService] 已有连接正在进行中，跳过');
      return false;
    }
    _connectInFlight = true;
    final connectStartedAt = DateTime.now();
    // 健康检查的后台撤销标记：TUN/VPN 失败提前抛出时，让并行的服务器连通检查立刻退出。
    var checksAborted = false;
    String? createdInstanceId;
    try {
      if (_nodeManagement.isRunning) {
        // 拆旧实例但保留本次新尝试的 linking 阶段，避免界面闪回空闲页。
        await disconnect(
          clearSession: false,
          abortLink: false,
          preservePhase: true,
        );
      }
      if (RuntimePlatform.isAndroid) {
        _vpnManager.startListening();
        if (!await _vpnManager.ensurePermission()) {
          appLogger.w('[ConnectionService] Android VPN 权限未授予');
          return false;
        }
        if (!_isLinkActive(epoch)) return false;
      }

      final fromGame = gameId != null && gameId.isNotEmpty
          ? await _gameRules.wantsUdpBroadcastRelay(gameId)
          : false;
      if (!_isLinkActive(epoch)) return false;
      final udpRelay = fromGame;
      final protocol = gameId != null && gameId.isNotEmpty
          ? await _gameRules.networkProtocol(gameId)
          : GameAssistNetworkProtocol.udp;
      if (!_isLinkActive(epoch)) return false;

      // LAN NAT：把房主虚拟 IP 映射成玩家物理网段里的假地址（仅 Android）。
      var natRule =
          RuntimePlatform.isAndroid && gameId != null && gameId.isNotEmpty
          ? _gameRules.lanNatRule(gameId)
          : null;
      // 启动时自动重连可能早于规则加载，补等一次本地规则（不等远程）。
      if (natRule == null &&
          RuntimePlatform.isAndroid &&
          gameId != null &&
          gameId.isNotEmpty) {
        await _gameRules.ensureLocalLoaded();
        natRule = _gameRules.lanNatRule(gameId);
      }
      String? lanNatFakeIp;
      _lanNatLog(
        'connect gameId=$gameId android=${RuntimePlatform.isAndroid} '
        'rule=${natRule?.ports}',
      );
      if (natRule != null) {
        lanNatFakeIp = await _pickLanNatFakeIp();
        _lanNatLog('fake=$lanNatFakeIp');
      }
      if (!_isLinkActive(epoch)) return false;

      final configToml = _p2pConfig.buildTomlConfig(
        networkName,
        secret,
        peersOverride: peersOverride,
        enableUdpBroadcastRelay: udpRelay,
        protocol: protocol,
        isDhcp: _appSettings.getIsDhcp(),
        isDhcpv6: _appSettings.getIsDhcpv6(),
        virtualIp: _appSettings.getVirtualIp(),
        virtualIpv6: _appSettings.getVirtualIpv6(),
      );
      appLogger.i(
        '[ConnectionService] $purpose 启动实例 network=$networkName '
        'shared_secret=true\n'
        '----- TOML begin -----\n'
        '$configToml'
        '----- TOML end -----',
      );
      createdInstanceId = await createInstance(
        configToml: configToml,
        watchEvent: true,
      );
      if (!_isLinkActive(epoch)) {
        await closeInstance(instanceId: createdInstanceId);
        createdInstanceId = null;
        return false;
      }
      appLogger.i('[ConnectionService] 实例已创建 id=$createdInstanceId');
      final isRunning = await _waitUntilRunning(
        createdInstanceId,
        isAborted: () => !_isLinkActive(epoch),
      );
      if (!_isLinkActive(epoch)) {
        await closeInstance(instanceId: createdInstanceId);
        createdInstanceId = null;
        return false;
      }
      if (!isRunning) {
        appLogger.e('[ConnectionService] 实例启动异常 id=$createdInstanceId');
        await closeInstance(instanceId: createdInstanceId);
        createdInstanceId = null;
        // 桌面端启动失败绝大多数是虚拟网卡没建起来（权限 / 驱动）。
        if (RuntimePlatform.isDesktop) {
          throw const ConnectionFailureException(_desktopTunFailureMessage);
        }
        return false;
      }

      await _bindPeerRpc(createdInstanceId);
      if (!_isLinkActive(epoch)) {
        await _unbindPeerRpc();
        await closeInstance(instanceId: createdInstanceId);
        createdInstanceId = null;
        return false;
      }
      _nodeManagement.setRunning(createdInstanceId);

      // 全平台：实例起来了但连不上任何服务器时，房间等于没有网络。
      // 只在真的配置了服务器时检查，避免把「无服务器」误判成连接失败。
      // 该检查与虚拟网卡 / Android VPN 就绪互不依赖，两件事并行等，
      // 否则会把「建网卡」和「连服务器」两段耗时直接相加。
      final peers = _p2pConfig.resolvePeers(peersOverride: peersOverride);
      final serverLinkCheck = peers.isEmpty
          ? null
          : _waitServerLink(
              createdInstanceId,
              isAborted: () => checksAborted || !_isLinkActive(epoch),
            );

      // 桌面端：实例「运行」不等于虚拟网卡可用，这里额外等一个明确的就绪信号，
      // 超时即判定 TUN 创建失败（常见于缺少管理员权限 / CAP_NET_ADMIN）。
      if (RuntimePlatform.isDesktop) {
        final tun = await _waitDesktopTun(
          createdInstanceId,
          isAborted: () => !_isLinkActive(epoch),
        );
        if (!_isLinkActive(epoch)) {
          checksAborted = true;
          await closeInstance(instanceId: createdInstanceId);
          createdInstanceId = null;
          return false;
        }
        if (!tun.ready) {
          throw ConnectionFailureException(
            tun.reason ?? _desktopTunFailureMessage,
          );
        }
      }

      if (RuntimePlatform.isAndroid) {
        final vpnOk = await _startAndroidVpnWhenIpReady(
          createdInstanceId,
          extraRoutes: lanNatFakeIp == null ? const [] : ['$lanNatFakeIp/32'],
        );
        if (!_isLinkActive(epoch)) {
          checksAborted = true;
          await disconnect(clearSession: false, abortLink: false);
          createdInstanceId = null;
          return false;
        }
        if (!vpnOk) {
          checksAborted = true;
          appLogger.e('[ConnectionService] Android VPN 启动失败，回滚连接');
          await disconnect(forceEndNotice: '虚拟网络（VPN）启动失败，请检查权限后重试');
          createdInstanceId = null;
          return false;
        }
        if (lanNatFakeIp != null && natRule != null) {
          try {
            await setLanNat(
              instanceId: createdInstanceId,
              fakeIp: lanNatFakeIp,
              ports: natRule.ports,
            );
            _lanNatLog('attached to $createdInstanceId');
          } catch (e) {
            _lanNatLog('attach failed: $e');
          }
        }
      }

      // 全平台：服务器连通检查（与上面的 TUN / VPN 等待并行）。
      if (serverLinkCheck != null) {
        final serverError = await serverLinkCheck;
        if (!_isLinkActive(epoch)) {
          await closeInstance(instanceId: createdInstanceId);
          createdInstanceId = null;
          return false;
        }
        if (serverError != null) {
          throw ConnectionFailureException(serverError);
        }
      }
      // 传输真正可用（TUN/VPN 就绪 + 服务器连通检查通过）才算 connected。
      _roomState.setConnected(true);
      _armGuestPresenceWatch();
      appLogger.i(
        '[ConnectionService] $purpose 连接就绪，耗时 '
        '${DateTime.now().difference(connectStartedAt).inMilliseconds}ms',
      );
      return true;
    } catch (e, st) {
      checksAborted = true;
      appLogger.e('[ConnectionService] 连接失败: $e', error: e, stackTrace: st);
      await _unbindPeerRpc();
      _disarmGuestPresenceWatch();
      if (createdInstanceId != null) {
        try {
          await closeInstance(instanceId: createdInstanceId);
        } catch (closeError, closeSt) {
          appLogger.e(
            '[ConnectionService] 回滚实例失败: $closeError',
            error: closeError,
            stackTrace: closeSt,
          );
        }
      }
      _nodeManagement.setStopped();
      _roomState.setConnected(false, clearSession: false);
      if (e is ConnectionFailureException) rethrow;
      final translated = _translateConnectionError(e);
      if (translated != e) throw translated;
      return false;
    } finally {
      _connectInFlight = false;
    }
  }

  /// [clearSession] 是否清空房间会话（乐观 UI 拆旧实例时可为 false）。
  /// [abortLink] 是否作废进行中的乐观连接（内部拆旧实例时应为 false）。
  Future<void> disconnect({
    String? forceEndNotice,
    bool clearSession = true,
    bool abortLink = true,
    bool preservePhase = false,
  }) async {
    if (abortLink) {
      _link.abort();
    }
    if (!preservePhase) {
      _roomState.connection.beginDisconnecting();
    }
    final session = _roomState.session.value;
    if (session?.isSteamTransport == true) {
      await _unbindPeerRpc();
      try {
        await _steam.stop();
      } catch (e) {
        appLogger.w('[ConnectionService] 关闭 Steam 组网失败: $e');
      }
    }
    await _roomAssist.stopAll();
    await _gameInject.stop();
    await _openGames.stop();

    _disarmGuestPresenceWatch();
    final instanceId = _nodeManagement.instanceId;
    if (RuntimePlatform.isAndroid) {
      await _vpnManager.stop();
    }
    // Steam 组网没有 EasyTier 实例，伪 instanceId 不能传给 Rust。
    if (instanceId != null &&
        instanceId != NodeManagementService.steamInstanceId) {
      try {
        await closeInstance(instanceId: instanceId);
      } catch (e, st) {
        appLogger.e('[ConnectionService] 断开异常: $e', error: e, stackTrace: st);
      }
    }
    _nodeManagement.setStopped();
    if (!preservePhase) {
      _roomState.setConnected(false, clearSession: clearSession);
    } else if (clearSession) {
      _roomState.setSession(null);
    }
    if (forceEndNotice != null && forceEndNotice.isNotEmpty) {
      _roomState.setForceEndNotice(forceEndNotice);
    }
    await _unbindPeerRpc();
  }

  void _armGuestPresenceWatch() {
    _disarmGuestPresenceWatch();
    final watch = GuestPresenceWatch();
    _guestPresenceOffline = false;
    _guestPresenceDispose = effect(() {
      final session = _roomState.session.value;
      final connected = _roomState.isConnected.value;
      final nodes = _nodeManagement.userNodes.value;
      final action = watch.evaluate(
        hasSession: session != null,
        isHostSession: session?.isHost ?? true,
        connected: connected,
        // 共享密码模式无法按凭据识别房主：有任意远端成员即视为房间仍有人。
        hasOtherMembers: nodes.any(
          (n) => !_nodeManagement.isLocalPeer(n.peerId),
        ),
      );
      switch (action) {
        case GuestPresenceAction.idle:
        case GuestPresenceAction.waiting:
          break;
        case GuestPresenceAction.online:
          _guestPresenceOffline = false;
          break;
        case GuestPresenceAction.offline:
          if (!_guestPresenceOffline) {
            _guestPresenceOffline = true;
            appLogger.w('[ConnectionService] 房间内无其他成员');
          }
          break;
      }
    });
  }

  void _disarmGuestPresenceWatch() {
    _guestPresenceDispose?.call();
    _guestPresenceDispose = null;
  }

  /// Steam 分支不经过 [_connectAndStartServices]，这里补齐与具体传输
  /// 无关的游戏辅助：Mono 注入与「开放游戏」列表。魔法墙仍只在 EasyTier 模式
  /// 启用（Steam 靠虚拟网卡泛洪做局域网发现，不做物理网卡旁路）。
  ///
  /// 辅助能力失败不应连带拆掉已经建立的房间，因此逐项吞掉异常并记日志。
  Future<void> _startGameAssist({
    required String gameId,
    required bool isHost,
  }) async {
    try {
      await _gameInject.startForRoom(gameId: gameId);
    } catch (e) {
      appLogger.w('[ConnectionService] 游戏注入启动失败: $e', error: e);
    }
    try {
      await _openGames.startForRoom(isHost: isHost, gameId: gameId);
    } catch (e) {
      appLogger.w('[ConnectionService] 开放游戏列表启动失败: $e', error: e);
    }
  }

  /// 等待 EasyTier 实例真正进入 Running，超时返回 false。
  ///
  /// `create_instance` 只是 spawn 了 `instance.start()` 就立刻返回，实例要经过
  /// Starting 才到 Running（建虚拟网卡、绑监听、DHCP 都是异步的），冷启动后第一次
  /// 开房这段最慢。旧实现只查一次 [isEasytierRunning] 就当成失败回滚，会出现
  /// "启动软件后的第一个房间刚建好就被拆掉"。
  ///
  /// [isAborted] 返回 true（如用户中途取消连接）时立即放弃等待。
  Future<bool> _waitUntilRunning(
    String instanceId, {
    required bool Function() isAborted,
    Duration timeout = const Duration(seconds: 8),
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (await isEasytierRunning(instanceId: instanceId)) return true;
      if (isAborted() || !DateTime.now().isBefore(deadline)) return false;
      await Future.delayed(interval);
    }
  }

  /// 桌面端等待虚拟网卡就绪。
  ///
  /// 三个就绪信号任一出现即视为成功：系统网络接口里出现 EasyTier 的虚拟网卡
  /// （`dev_name = ASGame`）、内核事件 `tun device ready`，或已轮询到虚拟 IP
  /// （事件可能在订阅前发出，后两者用于兜底）。同时监听 `tun device error`，
  /// 有明确错误时立即返回原因，不必等满超时。返回的 `reason` 为空表示被用户取消。
  Future<({bool ready, String? reason})> _waitDesktopTun(
    String instanceId, {
    required bool Function() isAborted,
    Duration timeout = desktopTunTimeout,
  }) async {
    var tunReady = false;
    String? tunError;
    void consume(CoreLogEventC event) {
      if (event.instanceId != instanceId) return;
      final message = event.message.trim();
      final lower = message.toLowerCase();
      if (lower.startsWith('tun device ready')) {
        tunReady = true;
      } else if (lower.startsWith('tun device error')) {
        tunError ??= message;
      }
    }

    // 事件可能在开始监听前就已发出（实例 Running 之后才进到这里），先补看缓冲。
    for (final event in _coreEvents.recentEventsFor(instanceId)) {
      consume(event);
    }
    final sub = _coreEvents.events.listen(consume);
    try {
      final deadline = DateTime.now().add(timeout);
      var tick = 0;
      while (true) {
        if (isAborted()) return (ready: false, reason: null);
        final error = tunError;
        if (error != null) {
          return (
            ready: false,
            reason:
                '虚拟网卡（TUN）创建失败：$error。'
                '请检查网络权限后重试（Windows 请以管理员身份运行，'
                'Linux 请确认已授予网络能力）。',
          );
        }
        if (tunReady || _nodeManagement.myVirtualIpv4.value.isNotEmpty) {
          return (ready: true, reason: null);
        }
        // 网卡枚举比事件更可靠，但开销大，约每秒查一次。
        if (tick % 5 == 0 && await _hasDesktopTunInterface()) {
          return (ready: true, reason: null);
        }
        tick++;
        if (!DateTime.now().isBefore(deadline)) {
          return (
            ready: false,
            reason:
                '虚拟网卡（TUN）在 ${timeout.inSeconds} 秒内未能创建成功，'
                '请检查网络权限后重试（Windows 请以管理员身份运行，'
                'Linux 请确认已授予网络能力）。',
          );
        }
        await Future.delayed(_healthCheckInterval);
      }
    } finally {
      await sub.cancel();
    }
  }

  /// 系统网络接口里是否已有 EasyTier 的虚拟网卡（`dev_name = ASGame`）。
  Future<bool> _hasDesktopTunInterface() async {
    try {
      final interfaces = await NetworkInterface.list();
      return interfaces.any(
        (interface) => interface.name.toLowerCase().contains('asgame'),
      );
    } catch (e) {
      appLogger.d('[ConnectionService] 枚举网络接口失败: $e');
      return false;
    }
  }

  /// 等待与任意服务器/对端建立连接；超时返回可读的失败原因，成功返回 null。
  ///
  /// 判定依据二选一：内核事件 `peer connection added`，或轮询到的节点列表里
  /// 出现非本机节点（覆盖事件订阅晚于连接建立的情况）。
  Future<String?> _waitServerLink(
    String instanceId, {
    required bool Function() isAborted,
    Duration timeout = serverLinkTimeout,
  }) async {
    var linked = false;
    String? firstError;
    void consume(CoreLogEventC event) {
      if (event.instanceId != instanceId) return;
      final message = event.message.trim();
      final lower = message.toLowerCase();
      if (lower.startsWith('peer connection added')) {
        linked = true;
      } else if (firstError == null && lower.startsWith('connect error')) {
        firstError = message;
      }
    }

    // 与 TUN 同理：连上服务器的日志可能在开始监听前就已发出，先补看缓冲。
    for (final event in _coreEvents.recentEventsFor(instanceId)) {
      consume(event);
    }
    final sub = _coreEvents.events.listen(consume);
    try {
      final deadline = DateTime.now().add(timeout);
      while (true) {
        if (isAborted()) return null;
        if (linked) return null;
        final status = _nodeManagement.networkStatus.value;
        final hasRemoteNode =
            status != null &&
            (status.totalNodes > BigInt.one ||
                status.nodes.any(
                  (n) =>
                      n.peerId != 0 && !_nodeManagement.isLocalPeer(n.peerId),
                ));
        if (hasRemoteNode) return null;
        if (!DateTime.now().isBefore(deadline)) {
          final detail = firstError == null ? '' : '（$firstError）';
          return '服务器连接失败$detail：${timeout.inSeconds} 秒内未能连接到任何服务器，'
              '请检查网络，或在「服务器」页更换服务器后重试。';
        }
        await Future.delayed(_healthCheckInterval);
      }
    } finally {
      await sub.cancel();
    }
  }

  void _lanNatLog(String message) {
    appLogger.d('[LANNAT] $message');
  }

  /// 在物理局域网网段里挑一个假地址（默认 .250）。
  ///
  /// 只认局域网网卡（Wi‑Fi / 以太网）：手机常同时有蜂窝网卡（rmnet/ccmni），
  /// 选到运营商网段（如 100.64/10）时假地址不在游戏所在局域网里，等于没映射。
  Future<String?> _pickLanNatFakeIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final candidates = <({String name, InternetAddress addr, bool lan})>[];
      for (final iface in ifaces) {
        final name = iface.name.toLowerCase();
        if (_isNonLanIface(name)) continue;
        for (final addr in iface.addresses) {
          final raw = addr.rawAddress;
          if (raw.length != 4) continue;
          if (!_isPrivateLanV4(raw)) continue;
          candidates.add((
            name: name,
            addr: addr,
            lan: _isWirelessOrEthernet(name),
          ));
        }
      }
      candidates.sort((a, b) => a.lan == b.lan ? 0 : (a.lan ? -1 : 1));
      for (final c in candidates) {
        final raw = c.addr.rawAddress;
        final last = raw[3] == 250 ? 249 : 250;
        final ip = '${raw[0]}.${raw[1]}.${raw[2]}.$last';
        _lanNatLog('pick $ip from ${c.name} ${c.addr.address}');
        return ip;
      }
    } catch (e) {
      _lanNatLog('NetworkInterface.list failed: $e');
    }
    try {
      final ip = await lanNatPickFakeIp();
      _lanNatLog('rust pick $ip');
      return ip;
    } catch (e) {
      _lanNatLog('rust pick failed: $e');
      return null;
    }
  }

  /// 虚拟网卡、蜂窝网卡、隧道等都不属于局域网。
  static bool _isNonLanIface(String name) =>
      name.startsWith('tun') ||
      name.startsWith('rmnet') ||
      name.startsWith('ccmni') ||
      name.startsWith('pdp') ||
      name.startsWith('clat') ||
      name.startsWith('dummy') ||
      name.startsWith('ip6tnl') ||
      name.startsWith('sit') ||
      name.startsWith('p2p') ||
      name.startsWith('v4-') ||
      name.contains('vethernet') ||
      name.contains('docker');

  static bool _isWirelessOrEthernet(String name) =>
      name.startsWith('wlan') ||
      name.startsWith('wifi') ||
      name.startsWith('eth') ||
      name.startsWith('ap');

  /// RFC1918 私网地址；排除 100.64/10（运营商 CGNAT）与 100.100.100.x 虚拟网。
  static bool _isPrivateLanV4(List<int> o) {
    if (o[0] == 10) return true;
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true;
    if (o[0] == 192 && o[1] == 168) return true;
    return false;
  }

  Future<bool> _startAndroidVpnWhenIpReady(
    String instanceId, {
    List<String> extraRoutes = const [],
  }) async {
    final completer = Completer<String?>();
    late final EffectCleanup dispose;
    dispose = effect(() {
      final currentInstance = _nodeManagement.currentInstanceId.value;
      if (currentInstance != instanceId) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final ip = _nodeManagement.myVirtualIpv4.value;
      if (ip.isNotEmpty && !completer.isCompleted) {
        completer.complete(ip);
      }
    });
    try {
      final vpnIp = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          appLogger.w('[ConnectionService] 等待虚拟 IP 超时');
          return null;
        },
      );
      if (vpnIp == null || vpnIp.isEmpty) return false;
      final vpnStarted = await _vpnManager.start(
        instanceId: instanceId,
        ipv4Addr: vpnIp,
        extraRoutes: extraRoutes,
      );
      if (!vpnStarted) {
        appLogger.w('[ConnectionService] Android VPN 启动失败');
      }
      return vpnStarted;
    } finally {
      dispose();
    }
  }

  Future<void> _bindPeerRpc(String instanceId) async {
    _peerRpc.bindInstance(instanceId);
    await _peerRpcRouter.start(instanceId);
  }

  Future<void> _unbindPeerRpc() async {
    _peerRpc.bindInstance(null);
    try {
      await _peerRpcRouter.stop();
    } catch (e) {
      appLogger.w('[ConnectionService] PeerRpcRouter 停止异常: $e');
    }
  }

  String _randomId(int len) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(
      len,
      (_) => alphabet[r.nextInt(alphabet.length)],
    ).join();
  }
}

/// 连接失败的明确原因（虚拟网卡创建失败 / 服务器连不上等）。
///
/// 与 [StateError] 不同，[toString] 直接返回可展示给用户的文案。
class ConnectionFailureException implements Exception {
  const ConnectionFailureException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 已有连接尝试正在进行，拒绝第二次建联（不是连接失败）。
class ConnectionBusyException implements Exception {
  const ConnectionBusyException();

  @override
  String toString() => '正在连接中，请稍候…';
}

/// 用户在乐观连接完成前离开/取消。
class ConnectionAbortedException implements Exception {
  const ConnectionAbortedException();

  @override
  String toString() => 'ConnectionAbortedException';
}

/// 乐观进房世代：离开/取消时 abort，进行中的连接看到过期则中止。
class ConnectionLinkEpoch {
  int _value = 0;

  int get current => _value;

  int begin() => ++_value;

  void abort() => _value++;

  bool isLive(int epoch) => epoch == _value;
}

/// 客机侧房主在线判定的结果。
enum GuestPresenceAction {
  /// 不适用（无会话 / 房主自己 / 未连接）：不改变在线状态。
  idle,

  /// 房间内仍有其他成员：房主在线。
  online,

  /// 暂无远端成员，但未超过宽限期：先不下结论。
  waiting,

  /// 持续无远端成员超过宽限期：判定房主离线。
  offline,
}

/// 客机侧「房主是否还在房间」的判定。
///
/// 从成员列表推断：共享密码模式无法按凭据识别房主，因此房间内只要有任意
/// 远端成员就视为房主仍在线；完全为空才开始计时，超过 [grace] 才判定离线，
/// 避免断线重连的抖动造成误判。抽成独立类以便脱离 signals / 原生调用单测。
class GuestPresenceWatch {
  GuestPresenceWatch({
    this.grace = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 判定离线前的宽限期。
  final Duration grace;
  final DateTime Function() _clock;

  DateTime? _missingSince;

  GuestPresenceAction evaluate({
    required bool hasSession,
    required bool isHostSession,
    required bool connected,
    required bool hasOtherMembers,
  }) {
    if (!hasSession || isHostSession || !connected) {
      _missingSince = null;
      return GuestPresenceAction.idle;
    }
    if (hasOtherMembers) {
      _missingSince = null;
      return GuestPresenceAction.online;
    }
    final now = _clock();
    final since = _missingSince ??= now;
    return now.difference(since) < grace
        ? GuestPresenceAction.waiting
        : GuestPresenceAction.offline;
  }

  void reset() => _missingSince = null;
}
