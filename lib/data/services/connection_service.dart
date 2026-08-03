import 'dart:async';
import 'dart:io';

import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/p2p_config_service.dart';
import 'package:astral_game/data/services/room_persistence_service.dart';
import 'package:astral_game/data/services/vpn_manager.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_client.dart';
import 'package:astral_game/data/services/peer_rpc/peer_rpc_router.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_rust_core/p2p_service.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals_core.dart';

/// 连接服务
///
/// 负责管理 P2P 网络连接、房间创建和加入等操作
class ConnectionService {
  ConnectionService(
    this._p2pService,
    this._p2pConfig,
    this._nodeManagement,
    this._roomPersistence,
    this._roomState,
    this._vpnManager,
  );

  final P2PService _p2pService;
  final P2PConfigService _p2pConfig;
  final NodeManagementService _nodeManagement;
  final RoomPersistenceService _roomPersistence;
  final RoomState _roomState;
  final VpnManager _vpnManager;

  bool _isConnecting = false;

  bool get isConnecting => _isConnecting;

  /// 连接到指定房间
  ///
  /// [roomName] 房间名称
  /// [roomPassword] 房间密码
  /// 返回连接是否成功
  Future<bool> connectToRoom(String roomName, String roomPassword) async {
    if (_isConnecting) {
      appLogger.w('[ConnectionService] 已有连接正在进行中，跳过');
      return false;
    }

    _isConnecting = true;

    try {
      if (_nodeManagement.isRunning) {
        await disconnect();
      }

      // 鉴权由 EasyTier 的 network_secret 在传输层完成，业务侧不再需要 token。
      if (Platform.isAndroid) {
        _vpnManager.startListening();
        if (!await _vpnManager.ensurePermission()) {
          appLogger.w('[ConnectionService] Android VPN 权限未授予，取消连接');
          return false;
        }
      }

      final configToml = _p2pConfig.buildTomlConfig(roomName, roomPassword);
      appLogger.d('[ConnectionService] 正在连接房间: $roomName');

      final instanceId = await _p2pService.createInstance(
        configToml: configToml,
        watchEvent: true,
      );

      final isRunning = await _p2pService.isEasytierRunning(instanceId);
      if (!isRunning) {
        appLogger.e('[ConnectionService] 连接失败：实例启动异常');
        return false;
      }

      // 与 Windows 等桌面完全一致：实例就绪即视为"连接已建立"，绑定 RPC、setRunning、
      // UI 跳转。本机虚拟 IPv4 不参与判定 —— 它什么时候被 DHCP 发出来都行，由
      // `NodeManagementService.myVirtualIpv4` signal 持续广播。
      // Android 唯一的差异：拿到本机虚拟 IPv4 后，把 VPN/TUN 拉起来；拉不起来也
      // 不影响房间生命周期。
      await _bindPeerRpc(instanceId);
      _nodeManagement.setRunning(instanceId);
      _roomState.setConnected(true);
      _roomState.setConnectedRoomName(roomName);
      final matched = _roomState.rooms
          .where((r) => r.roomName == roomName && r.password == roomPassword)
          .toList();
      if (matched.isNotEmpty) {
        _roomState.setSelectedRoom(matched.first);
      }
      appLogger.d('[ConnectionService] 实例已启动，进入房间: $instanceId');

      if (Platform.isAndroid) {
        unawaited(_startAndroidVpnWhenIpReady(instanceId));
      }
      return true;
    } catch (e, stackTrace) {
      appLogger.e(
        '[ConnectionService] 连接失败: $e',
        error: e,
        stackTrace: stackTrace,
      );
      await _unbindPeerRpc();
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// 断开当前连接
  Future<void> disconnect() async {
    final instanceId = _nodeManagement.instanceId;
    if (Platform.isAndroid) {
      await _vpnManager.stop();
    }
    if (instanceId != null) {
      try {
        await _p2pService.closeInstance(instanceId);
        appLogger.d('[ConnectionService] 已断开连接，实例ID: $instanceId');
      } catch (e, stackTrace) {
        appLogger.e(
          '[ConnectionService] 断开连接时发生错误: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
    _nodeManagement.setStopped();
    _roomState.setConnected(false);
    await _unbindPeerRpc();
  }

  /// 等到 [`NodeManagementService.myVirtualIpv4`] 这个 signal 派发出非空 IPv4 后，
  /// 把 Android VPN 拉起来。
  ///
  /// 这里**不轮询**：本身 NodeManagement 已经在以 1s 间隔轮询 `getNetworkStatus`
  /// 并写入 `myVirtualIpv4`，连接服务只需订阅。
  /// - 没有超时：DHCP 几秒、几十秒，甚至单人房间永远不来都不影响判定，房间始终在线。
  /// - 实例被替换/disconnect 时 `currentInstanceId` 会清空或切换，effect 自然退出。
  Future<void> _startAndroidVpnWhenIpReady(String instanceId) async {
    final completer = Completer<String?>();
    late final EffectCleanup dispose;
    dispose = effect(() {
      // 任意一个 signal 变化都会重跑：换实例/断开 → 退出；IP 到 → 派发。
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
      final vpnIp = await completer.future;
      if (vpnIp == null) {
        appLogger.d('[ConnectionService] 已断开或切换实例，跳过 Android VPN: $instanceId');
        return;
      }
      final vpnStarted = await _vpnManager.start(
        instanceId: instanceId,
        ipv4Addr: vpnIp,
      );
      if (!vpnStarted) {
        appLogger.w('[ConnectionService] Android VPN 启动失败，但房间继续保留');
      }
    } finally {
      dispose();
    }
  }

  Future<void> _bindPeerRpc(String instanceId) async {
    GetIt.I<PeerRpcClient>().bindInstance(instanceId);
    try {
      await GetIt.I<PeerRpcRouter>().start(instanceId);
    } catch (e, stackTrace) {
      appLogger.e(
        '[ConnectionService] PeerRpcRouter 启动失败: $e',
        error: e,
        stackTrace: stackTrace,
      );
      // 启动失败不阻断连接，业务侧可以重试拉资料；但路由器没起来意味着对端无法
      // 调本端的 user.getInfo 等，需要在日志里清晰提示。
    }
  }

  Future<void> _unbindPeerRpc() async {
    GetIt.I<PeerRpcClient>().bindInstance(null);
    try {
      await GetIt.I<PeerRpcRouter>().stop();
    } catch (e) {
      appLogger.w('[ConnectionService] PeerRpcRouter 停止异常: $e');
    }
  }

  /// 创建新房间
  ///
  /// 要求传入房间名，并生成 token 作为 EasyTier `network_secret`（房间密码）。
  /// 返回创建的房间信息。
  Future<RoomMod> createRoom({required String roomName}) async {
    final token = _p2pConfig.generateRoomCode();
    final shareCode = _p2pConfig.buildRoomShareCode(
      roomName: roomName,
      token: token,
    );
    return await _createAndPersistRoom(
      shareCode: shareCode,
      displayName: roomName.trim(),
      roomName: roomName.trim(),
      token: token,
    );
  }

  /// 加入已有房间
  ///
  /// [shareCode] 房间分享码：`随机码_房间名`
  /// 返回房间信息
  Future<RoomMod> joinRoom(String shareCode) async {
    final trimmed = shareCode.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('请输入房间分享码');
    }

    final parts = _p2pConfig.parseRoomShareCode(trimmed);
    if (parts == null) {
      throw const FormatException('分享码格式不正确，应为：随机码_房间名');
    }

    return await _createAndPersistRoom(
      shareCode: trimmed,
      displayName: parts.roomName,
      roomName: parts.roomName,
      token: parts.token,
    );
  }

  /// 创建并持久化房间
  Future<RoomMod> _createAndPersistRoom({
    required String shareCode,
    required String displayName,
    required String roomName,
    required String token,
  }) async {
    final safeDisplayName = displayName.trim();
    final safeRoomName = roomName.trim();
    final safeToken = token.trim();
    final safePrefix = safeToken.isEmpty
        ? 'unknown'
        : safeToken.substring(0, safeToken.length < 6 ? safeToken.length : 6);

    final finalNetworkName = safeRoomName.isEmpty
        ? 'Room_$safePrefix'
        : safeRoomName;
    final finalDisplayName = safeDisplayName.isEmpty
        ? finalNetworkName
        : safeDisplayName;
    final roomPassword = safeToken;

    final room = RoomMod(
      id: DateTime.now().millisecondsSinceEpoch,
      name: finalDisplayName,
      roomName: finalNetworkName,
      host: 'localhost',
      port: 11010,
      password: roomPassword,
      shareCode: shareCode,
      createdAt: DateTime.now(),
    );

    try {
      final updated = RoomPersistenceService.upsertJoinHistory(
        _roomState.rooms,
        room,
      );
      await _roomPersistence.saveRooms(updated);
      await _roomState.loadFromPersistence();
      final saved = _roomState.rooms
          .where((r) => r.shareCode == shareCode)
          .toList();
      _roomState.setSelectedRoom(saved.isNotEmpty ? saved.first : room);
      appLogger.d(
        '[ConnectionService] 已创建/加入房间: $finalDisplayName, shareCode: $shareCode',
      );
    } catch (e, stackTrace) {
      appLogger.e(
        '[ConnectionService] 保存房间失败: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }

    return room;
  }

  /// 移除房间
  ///
  /// [roomId] 房间 ID
  void removeRoom(int roomId) {
    _roomState.removeRoom(roomId);
    appLogger.d('[ConnectionService] 已移除房间: $roomId');
  }
}
