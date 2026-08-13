import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/server_mod.dart';
import 'package:astral_game/data/services/app_settings_service.dart';
import 'package:astral_game/data/services/game_assist_rules_service.dart';
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
import 'package:astral_rust_core/p2p_service.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals_core.dart';

/// 连接服务：建房 / 进房（9 位短码或离线 Base64）/ 会话，不落盘房间历史。
///
/// 进网方式：双方共享随机 [network_name] + [network_secret]（旧版密码进房）。
class ConnectionService {
  ConnectionService(
    this._p2pService,
    this._p2pConfig,
    this._nodeManagement,
    this._roomState,
    this._vpnManager,
    this._shareCodes,
    this._roomAssist,
    this._gameRules,
    this._appSettings,
    this._openGames,
  );

  final P2PService _p2pService;
  final P2PConfigService _p2pConfig;
  final NodeManagementService _nodeManagement;
  final RoomState _roomState;
  final VpnManager _vpnManager;
  final ShareCodeService _shareCodes;
  final RoomAssistService _roomAssist;
  final GameAssistRulesService _gameRules;
  final AppSettingsService _appSettings;
  final OpenGamesService _openGames;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  /// 已有短码/会话，EasyTier 仍在连接中（供房间卡「连接中」提示）。
  final isLinking = signal(false);

  /// 递增以作废进行中的乐观连接（例如用户在连接中点了离开）。
  int _linkEpoch = 0;

  EffectCleanup? _guestPresenceDispose;
  DateTime? _hostMissingSince;

  /// 最近一次创建/加入时生成的 EasyTier TOML（调试弹窗用）。
  String? lastConfigToml;

  /// 最近一次离线邀请串（短码服务失败时的回退）。
  String? lastOfflineInvite;

  /// 创建房间：先发短码并写入会话（UI 立刻可见），再开 EasyTier。
  Future<ActiveRoomSession> createAndConnect({
    required String gameId,
    required String gameName,
    String? displayName,
  }) async {
    lastConfigToml = null;
    lastOfflineInvite = null;
    _roomState.setPausedHost(null);
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
    );
    _roomState.setSession(session);
    final epoch = ++_linkEpoch;
    isLinking.value = true;

    var linked = false;
    try {
      final ok = await _connect(
        networkName: networkName,
        secret: secret,
        purpose: 'create',
        gameId: gameId,
        epoch: epoch,
      );
      if (epoch != _linkEpoch) {
        throw const ConnectionAbortedException();
      }
      if (!ok) {
        throw StateError('连接失败，请重试');
      }
      await _roomAssist.startForRoom(isHost: true, gameId: gameId);
      await _openGames.startForRoom(isHost: true, gameId: gameId);
      linked = true;
      return session;
    } on ConnectionAbortedException {
      rethrow;
    } catch (e) {
      if (!linked && epoch == _linkEpoch) {
        await disconnect(revokeShare: true, clearSession: true);
      }
      rethrow;
    } finally {
      if (epoch == _linkEpoch) {
        isLinking.value = false;
      }
    }
  }

  Future<ActiveRoomSession> joinWithInviteInput(String raw) async {
    final token = extractJoinToken(raw) ?? raw.trim();
    if (token.isEmpty) {
      throw StateError('请粘贴邀请链接、短码或离线邀请');
    }
    if (looksLikeShortCode(token)) {
      return joinWithShortCode(token);
    }
    if (looksLikeOfflineInvite(token)) {
      final payload = decodeOfflineInvite(token);
      return _joinWithPayload(payload, shortCode: null);
    }
    throw StateError('无法识别邀请，请使用 Astral 分享的链接');
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

  /// 加入房间：9 位短码。
  Future<ActiveRoomSession> joinWithShortCode(String code) async {
    lastConfigToml = null;
    final payload = await _shareCodes.fetch(code);
    return _joinWithPayload(payload, shortCode: code.trim());
  }

  Future<ActiveRoomSession> _joinWithPayload(
    RoomInvitePayload payload, {
    String? shortCode,
  }) async {
    lastConfigToml = null;
    if (payload.networkSecret.isEmpty) {
      throw StateError('邀请无效：缺少房间密码（请让房主用新版重新分享）');
    }
    final invitePeers =
        payload.peers.where((p) => p.uri.trim().isNotEmpty).toList();
    if (invitePeers.isEmpty) {
      throw StateError('邀请未包含服务器，无法加入（请让房主启用服务器后重新分享）');
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
    );
    _roomState.setSession(session);
    final epoch = ++_linkEpoch;
    isLinking.value = true;

    var linked = false;
    try {
      final ok = await _connect(
        networkName: payload.networkName,
        secret: payload.networkSecret,
        peersOverride: invitePeers,
        purpose: 'join',
        gameId: payload.gameId,
        epoch: epoch,
      );
      if (epoch != _linkEpoch) {
        throw const ConnectionAbortedException();
      }
      if (!ok) {
        throw StateError('连接失败，请重试');
      }
      await _roomAssist.startForRoom(isHost: false, gameId: session.gameId);
      await _openGames.startForRoom(isHost: false, gameId: session.gameId);
      linked = true;
      return session;
    } on ConnectionAbortedException {
      rethrow;
    } catch (e) {
      if (!linked && epoch == _linkEpoch) {
        await disconnect(revokeShare: false, clearSession: true);
      }
      rethrow;
    } finally {
      if (epoch == _linkEpoch) {
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

  /// 房主刷新分享：作废旧短码，用同一网名/密码重新上传。
  Future<({String? shortCode, String offlineInvite})> refreshShareInvite() async {
    final current = _roomState.session.value;
    if (current == null || !current.isHost) {
      throw StateError('仅房主可分享');
    }

    if (current.shortCode != null && current.adminToken != null) {
      try {
        await _shareCodes.revoke(current.shortCode!, current.adminToken!);
      } catch (e) {
        appLogger.w('[ConnectionService] 作废旧短码失败: $e');
      }
    }

    final hostPeers = _p2pConfig.enabledPeers();
    if (hostPeers.isEmpty) {
      throw StateError('请先启用至少一个服务器，再刷新分享');
    }

    final payload = RoomInvitePayload(
      gameId: current.gameId,
      gameName: current.gameName,
      networkName: current.networkName,
      networkSecret: current.networkSecret,
      peers: hostPeers,
      displayName: current.displayName,
    );
    final offline = encodeOfflineInvite(payload);
    lastOfflineInvite = offline;

    String? shortCode;
    String? adminToken;
    try {
      final created = await _shareCodes.create(payload);
      shortCode = created.code;
      adminToken = created.adminToken;
    } catch (e) {
      appLogger.w('[ConnectionService] 刷新短码失败，仅离线邀请: $e');
    }

    _roomState.setSession(
      current.copyWith(
        shortCode: shortCode,
        adminToken: adminToken,
      ),
    );
    return (shortCode: shortCode, offlineInvite: offline);
  }

  /// 兼容旧调用：只返回短码。
  Future<String> refreshShareCode() async {
    final r = await refreshShareInvite();
    final code = r.shortCode;
    if (code == null || code.isEmpty) {
      throw StateError('短码服务不可用，请复制离线邀请码');
    }
    return code;
  }

  Future<void> revokeCurrentShortCode() async {
    final s = _roomState.session.value;
    if (s?.shortCode == null || s?.adminToken == null) return;
    await _shareCodes.revoke(s!.shortCode!, s.adminToken!);
  }

  /// 离开房间：作废短码（若有）并关闭实例。
  Future<void> leaveRoom() async {
    await disconnect(revokeShare: true, pauseHost: false);
  }

  /// 房主暂时退出：保留可恢复快照，并作废旧短码（恢复时会发新码）。
  Future<void> pauseHostRoom() async {
    final session = _roomState.session.value;
    if (session == null || !session.isHost) {
      await leaveRoom();
      return;
    }
    await disconnect(revokeShare: true, pauseHost: true);
  }

  /// 房主用快照恢复同房间（同 networkName/secret）；重新上传短码。
  Future<ActiveRoomSession> resumeHostRoom() async {
    final snap = _roomState.pausedHost.value;
    if (snap == null) {
      throw StateError('没有可恢复的房间');
    }
    final hostPeers = _p2pConfig.enabledPeers();
    if (hostPeers.isEmpty) {
      throw StateError('请先启用至少一个服务器，再恢复房间');
    }

    lastConfigToml = null;
    lastOfflineInvite = null;

    final payload = RoomInvitePayload(
      gameId: snap.gameId,
      gameName: snap.gameName,
      networkName: snap.networkName,
      networkSecret: snap.networkSecret,
      peers: hostPeers,
      displayName: snap.displayName,
    );
    lastOfflineInvite = encodeOfflineInvite(payload);

    String? shortCode;
    String? adminToken;
    try {
      final created = await _shareCodes.create(payload);
      shortCode = created.code;
      adminToken = created.adminToken;
    } catch (e) {
      appLogger.w('[ConnectionService] 恢复房间短码失败: $e');
    }

    final session = ActiveRoomSession(
      isHost: true,
      gameId: snap.gameId,
      gameName: snap.gameName,
      networkName: snap.networkName,
      networkSecret: snap.networkSecret,
      displayName: snap.displayName,
      shortCode: shortCode,
      adminToken: adminToken,
    );
    _roomState.setPausedHost(null);
    _roomState.setSession(session);
    final epoch = ++_linkEpoch;
    isLinking.value = true;

    var linked = false;
    try {
      final ok = await _connect(
        networkName: snap.networkName,
        secret: snap.networkSecret,
        purpose: 'resume-host',
        gameId: snap.gameId,
        epoch: epoch,
      );
      if (epoch != _linkEpoch) {
        throw const ConnectionAbortedException();
      }
      if (!ok) {
        throw StateError('恢复连接失败，请重试');
      }
      _armGuestPresenceWatch();
      await _roomAssist.startForRoom(isHost: true, gameId: session.gameId);
      await _openGames.startForRoom(isHost: true, gameId: session.gameId);
      linked = true;
      return session;
    } on ConnectionAbortedException {
      rethrow;
    } catch (e) {
      if (!linked && epoch == _linkEpoch) {
        await disconnect(revokeShare: true, clearSession: true);
      }
      rethrow;
    } finally {
      if (epoch == _linkEpoch) {
        isLinking.value = false;
      }
    }
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
      if (_nodeManagement.isRunning) {
        await disconnect(
          revokeShare: false,
          pauseHost: false,
          clearSession: false,
          abortLink: false,
        );
      }
      if (Platform.isAndroid) {
        _vpnManager.startListening();
        if (!await _vpnManager.ensurePermission()) {
          appLogger.w('[ConnectionService] Android VPN 权限未授予');
          return false;
        }
        if (epoch != _linkEpoch) return false;
      }

      final fromGame = gameId != null && gameId.isNotEmpty
          ? await _gameRules.wantsUdpBroadcastRelay(gameId)
          : false;
      if (epoch != _linkEpoch) return false;
      final fromUser = _appSettings.isEnableUdpBroadcastRelay();
      final udpRelay = fromGame || fromUser;

      final configToml = _p2pConfig.buildTomlConfig(
        networkName,
        secret,
        peersOverride: peersOverride,
        enableUdpBroadcastRelay: udpRelay,
      );
      lastConfigToml = configToml;
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
      if (epoch != _linkEpoch) {
        await _p2pService.closeInstance(createdInstanceId);
        createdInstanceId = null;
        return false;
      }
      appLogger.i('[ConnectionService] 实例已创建 id=$createdInstanceId');
      final isRunning = await _p2pService.isEasytierRunning(createdInstanceId);
      if (epoch != _linkEpoch) {
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
      if (epoch != _linkEpoch) {
        await _unbindPeerRpc();
        await _p2pService.closeInstance(createdInstanceId);
        createdInstanceId = null;
        return false;
      }
      _nodeManagement.setRunning(createdInstanceId);
      _roomState.setConnected(true);
      _armGuestPresenceWatch();
      if (Platform.isAndroid) {
        final vpnOk = await _startAndroidVpnWhenIpReady(createdInstanceId);
        if (epoch != _linkEpoch) {
          await disconnect(
            revokeShare: false,
            pauseHost: false,
            clearSession: false,
            abortLink: false,
          );
          createdInstanceId = null;
          return false;
        }
        if (!vpnOk) {
          appLogger.e('[ConnectionService] Android VPN 启动失败，回滚连接');
          await disconnect(
            revokeShare: false,
            pauseHost: false,
            forceEndNotice: '虚拟网络（VPN）启动失败，请检查权限后重试',
            clearSession: true,
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
      final msg = e.toString().toLowerCase();
      if (Platform.isWindows &&
          (msg.contains('tun') ||
              msg.contains('wintun') ||
              msg.contains('access is denied') ||
              msg.contains('privilege'))) {
        throw StateError('虚拟网卡启动失败，请以管理员身份重新运行 Astral Game');
      }
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// [revokeShare] 作废当前短码；[pauseHost] 房主保留可恢复快照。
  /// [clearSession] 是否清空房间会话（乐观 UI 拆旧实例时可为 false）。
  /// [abortLink] 是否作废进行中的乐观连接（内部拆旧实例时应为 false）。
  Future<void> disconnect({
    bool revokeShare = false,
    bool pauseHost = false,
    String? forceEndNotice,
    bool clearSession = true,
    bool abortLink = true,
  }) async {
    if (abortLink) {
      _linkEpoch++;
    }
    await _roomAssist.stopAll();
    await _openGames.stop();
    if (abortLink) {
      isLinking.value = false;
    }

    final session = _roomState.session.value;
    if (pauseHost && session != null && session.isHost) {
      _roomState.setPausedHost(HostResumeSnapshot.fromSession(session));
    } else if (revokeShare || forceEndNotice != null) {
      if (!pauseHost) {
        _roomState.setPausedHost(null);
      }
    }

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
    if (Platform.isAndroid) {
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
    GetIt.I<PeerRpcClient>().bindInstance(instanceId);
    await GetIt.I<PeerRpcRouter>().start(instanceId);
  }

  Future<void> _unbindPeerRpc() async {
    GetIt.I<PeerRpcClient>().bindInstance(null);
    try {
      await GetIt.I<PeerRpcRouter>().stop();
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
