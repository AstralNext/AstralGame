import 'dart:async';
import 'dart:math';

import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/game_assist_rules.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
import 'package:astral_game/data/services/game_inject_service.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/open_games_service.dart';
import 'package:astral_game/data/services/p2p_config_service.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_client.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_router.dart';
import 'package:astral_game/data/services/room_assist_service.dart';
import 'package:astral_game/data/services/share_code_service.dart';
import 'package:astral_game/data/services/vpn_manager.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:astral_rust_core/p2p_service.dart';
import 'package:signals/signals_core.dart';

/// 连接服务：建房 / 进房（6 位 32 进制短码或离线 Base64）/ 会话，不落盘房间历史。
///
/// 进网方式：双方共享随机 [network_name] + [network_secret]。
class ConnectionService {
  ConnectionService(
    this._p2pService,
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
  );

  final P2PService _p2pService;
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

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  /// 已有短码/会话，EasyTier 仍在连接中（供房间卡「连接中」提示）。
  final isLinking = signal(false);

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
    bool armGuestWatch = false,
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
    if (armGuestWatch) _armGuestPresenceWatch();
    await _roomAssist.startForRoom(isHost: isHost, gameId: gameId);
    await _gameInject.startForRoom(gameId: gameId);
    await _openGames.startForRoom(isHost: isHost, gameId: gameId);
  }

  EffectCleanup? _guestPresenceDispose;
  DateTime? _hostMissingSince;

  /// 最近一次离线邀请串（短码服务失败时的回退）。
  String? lastOfflineInvite;

  /// 创建房间：先发短码并写入会话（UI 立刻可见），再开 EasyTier。
  Future<ActiveRoomSession> createAndConnect({
    required String gameId,
    required String gameName,
    String? displayName,
  }) async {
    lastOfflineInvite = null;
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
    String? adminToken;
    try {
      final created = await _shareCodes.create(payload);
      shortCode = created.code;
      adminToken = created.adminToken;
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
      adminToken: adminToken,
      peers: hostPeers,
    );
    _roomState.setSession(session);
    final epoch = _link.begin();
    isLinking.value = true;

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
      return session;
    } on ConnectionAbortedException {
      rethrow;
    } catch (e) {
      if (!linked && _isLinkActive(epoch)) {
        await disconnect(revokeShare: true);
      }
      rethrow;
    } finally {
      if (_isLinkActive(epoch)) {
        isLinking.value = false;
      }
    }
  }

  /// 解析邀请输入（短码/离线）并返回完整 payload，**不真正加入房间**。
  /// 用于「⭐ 解析并收藏」等场景。
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
    final resolved = await resolveInvitePayload(raw);
    return joinWithPayload(
      resolved.payload,
      shortCode: resolved.shortCode,
    );
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

  /// 为任意 [RoomInvitePayload] 动态创建一条新短码（不需要 adminToken，任何人都能调）。
  ///
  /// 收藏页分享、成员侧临时分享都走这个入口。创建成功后**不会**自动写入 session，
  /// 调用方决定是否持久化（如 bookmark.lastShareCode）。
  Future<({String code, String adminToken, String expiresAt})>
      createShareCodeForPayload(RoomInvitePayload payload) {
    return _shareCodes.create(payload);
  }

  /// 为当前会话动态创建一条新短码（房主/成员均可调）。
  Future<({String code, String adminToken, String expiresAt})>
      createShareCodeForCurrentSession() {
    final session = _roomState.session.value;
    if (session == null) {
      throw StateError('未连接房间，无法生成短码');
    }
    final payload = payloadFromCurrentSession();
    if (payload == null) {
      throw StateError('当前会话缺少配置，无法生成短码');
    }
    return _shareCodes.create(payload);
  }

  /// 加入房间：6 位 32 进制短码。
  Future<ActiveRoomSession> joinWithShortCode(String code) async {
    final normalized = normalizeShareCode(code);
    final payload = await _shareCodes.fetch(normalized);
    return joinWithPayload(payload, shortCode: normalized);
  }

  /// 从任意 [RoomInvitePayload] 加入；收藏功能用它跳过短码服务。
  Future<ActiveRoomSession> joinWithPayload(
    RoomInvitePayload payload, {
    String? shortCode,
  }) =>
      _joinWithPayload(payload, shortCode: shortCode);

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
    );
  }

  Future<ActiveRoomSession> _joinWithPayload(
    RoomInvitePayload payload, {
    String? shortCode,
  }) async {
    final invitePeers = joinableInvitePeers(payload);

    // 如果没有短码（从收藏/离线加入），自动 create 一条存进 session，方便后续分享
    String? resolvedShortCode = shortCode;
    String? adminToken;
    if (resolvedShortCode == null || resolvedShortCode.isEmpty) {
      try {
        final created = await _shareCodes.create(payload);
        resolvedShortCode = created.code;
        adminToken = created.adminToken;
      } catch (e) {
        appLogger.w('[ConnectionService] 自动创建短码失败: $e');
      }
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
      shortCode: resolvedShortCode,
      adminToken: adminToken,
      peers: invitePeers,
    );
    _roomState.setSession(session);
    final epoch = _link.begin();
    isLinking.value = true;

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
      // 加入成功：如果 session 里有新 create 的短码（从收藏/离线加入的情况），
      // 回写到匹配的 bookmark，之后在收藏页点分享就能直接复用
      if (resolvedShortCode != null && resolvedShortCode.isNotEmpty) {
        unawaited(_roomState.refreshBookmarkShareCode(
          payload,
          shortCode: resolvedShortCode,
          adminToken: adminToken,
        ));
      }
      return session;
    } on ConnectionAbortedException {
      rethrow;
    } catch (e) {
      if (!linked && _isLinkActive(epoch)) {
        await disconnect();
      }
      rethrow;
    } finally {
      if (_isLinkActive(epoch)) {
        isLinking.value = false;
      }
    }
  }

  /// 导出当前离线邀请（优先缓存；否则用会话重建）。
  String? currentOfflineInvite() {
    final cached = lastOfflineInvite?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    final session = _roomState.session.value;
    if (session == null || !session.isHost) return null;
    if (session.networkSecret.isEmpty) return null;
    final hostPeers = _p2pConfig.enabledPeers();
    if (hostPeers.isEmpty) return null;
    final payload = RoomInvitePayload(
      gameId: session.gameId,
      gameName: session.gameName,
      networkName: session.networkName,
      networkSecret: session.networkSecret,
      peers: hostPeers,
      displayName: session.displayName,
    );
    return encodeOfflineInvite(payload);
  }

  /// 离开房间：作废短码（若有）并关闭实例。
  Future<void> leaveRoom() async {
    await disconnect(revokeShare: true);
  }

  Future<bool> _connect({
    required String networkName,
    required String secret,
    List<PeerEndpoint>? peersOverride,
    String purpose = 'connect',
    String? gameId,
    required int epoch,
  }) async {
    if (_isConnecting) {
      appLogger.w('[ConnectionService] 已有连接正在进行中，跳过');
      return false;
    }
    _isConnecting = true;
    String? createdInstanceId;
    try {
      await _p2pService.ensureInitialized();
      if (_nodeManagement.isRunning) {
        await disconnect(
          clearSession: false,
          abortLink: false,
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
      final fromUser = _appSettings.isEnableUdpBroadcastRelay();
      final udpRelay = fromGame || fromUser;
      final protocol = gameId != null && gameId.isNotEmpty
          ? await _gameRules.networkProtocol(gameId)
          : GameAssistNetworkProtocol.udp;
      if (!_isLinkActive(epoch)) return false;

      final configToml = _p2pConfig.buildTomlConfig(
        networkName,
        secret,
        peersOverride: peersOverride,
        enableUdpBroadcastRelay: udpRelay,
        protocol: protocol,
      );
      appLogger.i(
        '[ConnectionService] $purpose 启动实例 network=$networkName '
        'shared_secret=true\n'
        '----- TOML begin -----\n'
        '$configToml'
        '----- TOML end -----',
      );
      createdInstanceId = await _p2pService.createInstance(
        configToml: configToml,
        watchEvent: true,
      );
      if (!_isLinkActive(epoch)) {
        await _p2pService.closeInstance(createdInstanceId);
        createdInstanceId = null;
        return false;
      }
      appLogger.i('[ConnectionService] 实例已创建 id=$createdInstanceId');
      final isRunning = await _p2pService.isEasytierRunning(createdInstanceId);
      if (!_isLinkActive(epoch)) {
        await _p2pService.closeInstance(createdInstanceId);
        createdInstanceId = null;
        return false;
      }
      if (!isRunning) {
        appLogger.e('[ConnectionService] 实例启动异常 id=$createdInstanceId');
        await _p2pService.closeInstance(createdInstanceId);
        createdInstanceId = null;
        return false;
      }

      await _bindPeerRpc(createdInstanceId);
      if (!_isLinkActive(epoch)) {
        await _unbindPeerRpc();
        await _p2pService.closeInstance(createdInstanceId);
        createdInstanceId = null;
        return false;
      }
      _nodeManagement.setRunning(createdInstanceId);
      _roomState.setConnected(true);
      _armGuestPresenceWatch();
      if (RuntimePlatform.isAndroid) {
        final vpnOk = await _startAndroidVpnWhenIpReady(createdInstanceId);
        if (!_isLinkActive(epoch)) {
          await disconnect(
            clearSession: false,
            abortLink: false,
          );
          createdInstanceId = null;
          return false;
        }
        if (!vpnOk) {
          appLogger.e('[ConnectionService] Android VPN 启动失败，回滚连接');
          await disconnect(
            forceEndNotice: '虚拟网络（VPN）启动失败，请检查权限后重试',
          );
          createdInstanceId = null;
          return false;
        }
      }
      return true;
    } catch (e, st) {
      appLogger.e('[ConnectionService] 连接失败: $e', error: e, stackTrace: st);
      await _unbindPeerRpc();
      _disarmGuestPresenceWatch();
      if (createdInstanceId != null) {
        try {
          await _p2pService.closeInstance(createdInstanceId);
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
      final translated = _translateConnectionError(e);
      if (translated != e) throw translated;
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// [revokeShare] 作废当前短码。
  /// [clearSession] 是否清空房间会话（乐观 UI 拆旧实例时可为 false）。
  /// [abortLink] 是否作废进行中的乐观连接（内部拆旧实例时应为 false）。
  Future<void> disconnect({
    bool revokeShare = false,
    String? forceEndNotice,
    bool clearSession = true,
    bool abortLink = true,
  }) async {
    if (abortLink) {
      _link.abort();
    }
    await _roomAssist.stopAll();
    await _gameInject.stop();
    await _openGames.stop();
    if (abortLink) {
      isLinking.value = false;
    }

    final session = _roomState.session.value;

    if (revokeShare &&
        session != null &&
        session.isHost &&
        session.shortCode != null &&
        session.adminToken != null) {
      try {
        await _shareCodes.revoke(session.shortCode!, session.adminToken!);
        appLogger.i('[ConnectionService] 已作废短码 ${session.shortCode}');
      } catch (e) {
        appLogger.w('[ConnectionService] 作废短码失败: $e');
      }
    }

    _disarmGuestPresenceWatch();
    final instanceId = _nodeManagement.instanceId;
    if (RuntimePlatform.isAndroid) {
      await _vpnManager.stop();
    }
    if (instanceId != null) {
      try {
        await _p2pService.closeInstance(instanceId);
      } catch (e, st) {
        appLogger.e('[ConnectionService] 断开异常: $e', error: e, stackTrace: st);
      }
    }
    _nodeManagement.setStopped();
    _roomState.setConnected(false, clearSession: clearSession);
    if (forceEndNotice != null && forceEndNotice.isNotEmpty) {
      _roomState.setForceEndNotice(forceEndNotice);
    }
    await _unbindPeerRpc();
  }

  void _armGuestPresenceWatch() {
    _disarmGuestPresenceWatch();
    _hostMissingSince = null;
    _guestPresenceDispose = effect(() {
      final session = _roomState.session.value;
      final connected = _roomState.isConnected.value;
      final nodes = _nodeManagement.userNodes.value;
      if (session == null || session.isHost || !connected) {
        _hostMissingSince = null;
        return;
      }
      // 共享密码模式无法按凭据识别房主：有任意远端成员即视为房间仍有人。
      final hasOther = nodes.any(
        (n) => !_nodeManagement.isLocalPeer(n.peerId),
      );
      if (hasOther) {
        _hostMissingSince = null;
        if (!_roomState.hostOnline.value) {
          _roomState.setHostOnline(true);
        }
        return;
      }
      _hostMissingSince ??= DateTime.now();
      if (DateTime.now().difference(_hostMissingSince!) <
          const Duration(seconds: 10)) {
        return;
      }
      if (_roomState.hostOnline.value) {
        _roomState.setHostOnline(false);
        appLogger.w('[ConnectionService] 房间内无其他成员');
      }
    });
  }

  void _disarmGuestPresenceWatch() {
    _guestPresenceDispose?.call();
    _guestPresenceDispose = null;
    _hostMissingSince = null;
  }

  Future<bool> _startAndroidVpnWhenIpReady(String instanceId) async {
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
    return List.generate(len, (_) => alphabet[r.nextInt(alphabet.length)])
        .join();
  }
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
