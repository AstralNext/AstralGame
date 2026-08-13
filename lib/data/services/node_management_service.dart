import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:get_it/get_it.dart';
import 'package:signals/signals_core.dart';
import 'package:astral_game/utils/avatar_hash.dart';
import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_rust_core/p2p_service.dart';

import '../models/enhanced_node_info.dart';
import '../models/room_traffic_stats.dart';
import 'app_settings_service.dart';
import 'connectivity_status_service.dart';
import 'firewall_service.dart';
import 'peer_rpc/peer_rpc_client.dart' show PeerRpcClient;
import 'peer_rpc/peer_rpc_exception.dart';

/// 节点管理服务
///
/// 负责：
/// - 管理网络中的节点信息
/// - 轮询网络状态
/// - 获取节点头像和昵称
/// - 发送节点事件
class NodeManagementService {
  final _p2pService = GetIt.I<P2PService>();
  final _appSettings = GetIt.I<AppSettingsService>();

  /// 是否打印“每秒轮询细节”日志（非常刷屏，默认关闭）
  static const bool _verbosePollLogs = false;

  /// 用户节点列表
  final userNodes = signal<List<EnhancedNodeInfo>>([]);

  /// 当前实例 ID
  final currentInstanceId = signal<String?>(null);

  /// 网络状态
  final networkStatus = signal<KVNetworkStatus?>(null);

  /// 当前用户头像
  final currentUserAvatar = signal<Uint8List?>(null);

  /// 当前用户名
  final currentUsername = signal<String>('');

  /// 本机的虚拟网 IPv4（不带 CIDR）。轮询时从 `userNodes` 中取 peer_id=0 的
  /// 哨兵节点的 ipv4。未连接 / 尚未拿到地址 / DHCP 未分配时为空字符串。
  final myVirtualIpv4 = signal<String>('');

  /// 房间流量：对端合计的累计上下行 + 实时速率。
  final roomTraffic = signal<RoomTrafficStats>(RoomTrafficStats.zero);

  Timer? _pollingTimer;
  int _pollTick = 0;
  /// 已连接但尚未拿到虚拟 IP 时，节流告警，避免每秒刷屏。
  DateTime? _noIpSince;
  DateTime? _lastNoIpWarnAt;

  BigInt? _prevTrafficRx;
  BigInt? _prevTrafficTx;
  DateTime? _prevTrafficAt;

  /// 本机在当前 EasyTier instance 内的 peer_id。`null` 表示尚未取到（首次轮询
  /// 期间会在后台异步刷新）。用于在拉取资料时把"自己"过滤掉，避免无意义的
  /// 自调自请求把日志刷到屏幕上。
  int? _myPeerId;

  /// `astral_rust_core` 为本机节点合成的哨兵 peer_id（见 `LOCAL_SYNTHETIC_PEER_ID`）。
  /// 这是一个常量 0；它会出现在 `userNodes` 里但不是真实的可寻址节点。
  static const int _localSyntheticPeerId = 0;

  /// 控制 `user.getInfo` 调用频率：缺少客户端环境字段时较快重试。
  static const Duration _peerInfoCooldownMissingEnv = Duration(seconds: 3);
  /// 网络/防火墙等会变的字段：较短间隔拉取对端。
  static const Duration _peerInfoCooldownHasEnv = Duration(seconds: 5);

  /// 最近一次对每个 peer 发起 `user.getInfo` 的时间（用于节流，避免每秒整表二次刷新）。
  final Map<int, DateTime> _peerInfoFetchStartedAt = {};

  final List<EffectCleanup> _envListenerDisposers = [];
  Timer? _firewallRefreshTimer;

  /// 轮询间隔（用户列表需要更及时：1 秒）
  static const Duration _pollingInterval = Duration(seconds: 1);

  String? get instanceId => currentInstanceId.value;
  bool get isRunning => currentInstanceId.value != null;

  /// 与仪表盘「在线用户」列表一致（含本机，排除公共服务器节点）。
  List<EnhancedNodeInfo> get onlinePeersForDisplay {
    return userNodes.value
        .where((n) => !n.hostname.startsWith(AppConstants.publicServerHostname))
        .toList();
  }

  /// 启动节点管理
  void start(String instanceId) {
    currentInstanceId.value = instanceId;
    _myPeerId = null;
    _noIpSince = DateTime.now();
    _lastNoIpWarnAt = null;
    myVirtualIpv4.value = '';
    _resetRoomTraffic();
    // 后台异步取本机 peer_id，不阻塞 polling 启动；取到之前 polling 已经会用
    // `peerId == 0` 这个守卫挡掉合成本机节点。
    unawaited(_refreshMyPeerId(instanceId));
    _bindEnvListeners();
    if (Platform.isWindows && GetIt.I.isRegistered<FirewallService>()) {
      unawaited(GetIt.I<FirewallService>().refreshPrivateProfile());
      _firewallRefreshTimer?.cancel();
      _firewallRefreshTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) {
          if (currentInstanceId.value == null) return;
          unawaited(GetIt.I<FirewallService>().refreshPrivateProfile());
        },
      );
    }
    _startPolling(instanceId);
    appLogger.i('[NodeManagementService] 已启动，实例ID: $instanceId');
  }

  /// 停止节点管理
  void stop() {
    _stopPolling();
    _unbindEnvListeners();
    _firewallRefreshTimer?.cancel();
    _firewallRefreshTimer = null;
    currentInstanceId.value = null;
    _myPeerId = null;
    userNodes.value = [];
    myVirtualIpv4.value = '';
    _resetRoomTraffic();
    _noIpSince = null;
    _lastNoIpWarnAt = null;
    _peerInfoFetchStartedAt.clear();
    appLogger.d('[NodeManagementService] 已停止');
  }

  Future<void> _refreshMyPeerId(String instanceId) async {
    try {
      final id = await _p2pService.myPeerId(instanceId);
      // 防止 stop() 之后才返回时把状态污染回去。
      if (currentInstanceId.value == instanceId) {
        _myPeerId = id;
        if (_verbosePollLogs) {
          appLogger.d('[NodeManagementService] 本机 peer_id=$id');
        }
      }
    } catch (e) {
      appLogger.w('[NodeManagementService] 获取本机 peer_id 失败: $e');
    }
  }

  /// 开始轮询网络状态
  void _startPolling(String instanceId) {
    _stopPolling();
    _pollNetworkStatus(instanceId);
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      if (_verbosePollLogs) {
        // 用于确认轮询“确实在每秒触发”（非常刷屏）
        _pollTick++;
        appLogger.d('[NodeManagementService] poll tick=$_pollTick');
      }
      _pollNetworkStatus(instanceId);
    });
  }

  /// 停止轮询
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _bindEnvListeners() {
    _unbindEnvListeners();
    if (GetIt.I.isRegistered<ConnectivityStatusService>()) {
      _envListenerDisposers.add(effect(() {
        GetIt.I<ConnectivityStatusService>().current.value;
        _onVolatileEnvChanged();
      }));
    }
    if (GetIt.I.isRegistered<FirewallService>()) {
      _envListenerDisposers.add(effect(() {
        GetIt.I<FirewallService>().privateProfileEnabled.value;
        _onVolatileEnvChanged();
      }));
    }
  }

  void _unbindEnvListeners() {
    for (final dispose in _envListenerDisposers) {
      dispose();
    }
    _envListenerDisposers.clear();
  }

  /// 本机网络/防火墙变化：立即刷新列表中的本机行，并允许下一轮 poll 重拉对端环境。
  void _onVolatileEnvChanged() {
    _refreshLocalEnvInUserList();
    _peerInfoFetchStartedAt.clear();
  }

  void _refreshLocalEnvInUserList() {
    final nodes = userNodes.value;
    if (nodes.isEmpty) return;
    final updated = nodes.map((n) {
      if (!_isLocalPeer(n.peerId)) return n;
      return _enrichLocalNode(n);
    }).toList();
    if (!_sameUserNodesUiSnapshot(nodes, updated)) {
      userNodes.value = updated;
    }
  }

  /// 轮询网络状态
  ///
  /// 获取最新的网络状态和节点信息
  Future<void> _pollNetworkStatus(String instanceId) async {
    try {
      final status = await _p2pService.getNetworkStatus(instanceId);
      final newTotalNodes = status.totalNodes;
      final newNodesList = status.nodes;

      // 旧项目里网络状态是“持续更新”的；仅在 Rust 快照相对上次确有变化时再触发 signal，
      // 避免其它监听 `networkStatus` 的组件无意义每秒重建。
      final nextNetworkStatus = KVNetworkStatus(
        totalNodes: newTotalNodes,
        nodes: List.from(newNodesList),
      );
      final prevNs = networkStatus.value;
      if (prevNs == null || prevNs != nextNetworkStatus) {
        networkStatus.value = nextNetworkStatus;
      }

      final currentNodes = Map<int, EnhancedNodeInfo>.fromEntries(
        userNodes.value.map((node) => MapEntry(node.peerId, node)),
      );

      // 每次轮询都“重建一份规范化节点表”，避免历史列表里混入重复项后无法被增量逻辑清理。
      // 去重主键：peerId（Rust 侧也会去重，但这里兜底保证 UI 列表不出现重复条目）。
      final newNodes = <int, EnhancedNodeInfo>{};
      for (final node in newNodesList) {
        // 公共服务器仅用于中继/目录，不应出现在“在线用户”列表。
        if (node.hostname.startsWith(AppConstants.publicServerHostname)) continue;
        final prev = currentNodes[node.peerId];
        var enhanced = EnhancedNodeInfo(
          baseInfo: node,
          // 合并 RPC 写入的 metadata（含 peerOsVersion 等），否则下一轮 poll 会清空，
          // UI 上表现为版本行「闪一下又没了」。
          metadata: {...?prev?.metadata},
          customName: prev?.customName,
          avatar: prev?.avatar,
        );
        // 本机条目（合成哨兵 peer_id=0 或真实本机 peer_id）直接用本地资料填充，
        // 不走 RPC：自己问自己没意义，而且能保证 UI 列表里"自己"始终最新。
        if (_isLocalPeer(node.peerId)) {
          enhanced = _enrichLocalNode(enhanced);
        }
        newNodes[node.peerId] = enhanced;
      }

      // 纯周期获取：每次轮询都全量覆盖列表（不依赖事件驱动）
      final normalized = newNodes.values.toList()
        ..sort((a, b) => a.peerId.compareTo(b.peerId));

      final activePeerIds = normalized.map((n) => n.peerId).toSet();
      _peerInfoFetchStartedAt.removeWhere((id, _) => !activePeerIds.contains(id));

      final prevUsers = userNodes.value;
      if (!_sameUserNodesUiSnapshot(prevUsers, normalized)) {
        userNodes.value = normalized;
      }

      // 本机虚拟 IP：优先取 `astral_rust_core` 合成的本机哨兵节点（peer_id=0）
      // 的 ipv4；个别状态下 EasyTier 的 routes 表里也可能直接给本机一条
      // 真实 peer_id 的条目，做一个兜底匹配。任意一种都拿不到时清空。
      final myIp = _resolveMyVirtualIpv4(normalized);
      if (myIp != myVirtualIpv4.value) {
        final prev = myVirtualIpv4.value;
        myVirtualIpv4.value = myIp;
        appLogger.i(
          '[NodeManagementService] 本机虚拟 IP: '
          '${prev.isEmpty ? '(空)' : prev} -> ${myIp.isEmpty ? '(空)' : myIp}',
        );
      }
      _trackMissingVirtualIp(myIp, normalized);
      _updateRoomTraffic(newNodesList);

      if (_verbosePollLogs) {
        // 每秒打印“本次实际获取到的节点列表”（非常刷屏）
        final nodesPreview = normalized
            .map((n) => '${n.peerId}:${n.hostname}:${n.ipv4.split('/').first}')
            .join(', ');
        appLogger.d(
          '[NodeManagementService] poll users(total=${normalized.length}, rawTotal=$newTotalNodes) [$nodesPreview]',
        );
      }

      // 拉取对端资料（昵称/头像/客户端环境）：节流，避免每秒对每个 peer 再打一遍 RPC 导致列表疯狂重建。
      for (final n in normalized) {
        _maybeFetchNodeInfo(n);
      }
    } catch (e, stackTrace) {
      appLogger.e('[NodeManagementService] 轮询网络状态失败: $e', error: e, stackTrace: stackTrace);
    }
  }

  /// 判断给定 peer_id 是否对应"本机"（合成哨兵或真实本机）。
  bool _isLocalPeer(int peerId) =>
      peerId == _localSyntheticPeerId ||
      (_myPeerId != null && peerId == _myPeerId);

  /// 是否为本机节点（含 Rust 合成本机哨兵 id）。
  bool isLocalPeer(int peerId) => _isLocalPeer(peerId);

  void _resetRoomTraffic() {
    _prevTrafficRx = null;
    _prevTrafficTx = null;
    _prevTrafficAt = null;
    roomTraffic.value = RoomTrafficStats.zero;
  }

  /// 汇总对端 rx/tx，差分得到实时速率（不含本机哨兵与公共服务器）。
  void _updateRoomTraffic(List<KVNodeInfo> rawNodes) {
    var rx = BigInt.zero;
    var tx = BigInt.zero;
    for (final n in rawNodes) {
      if (n.hostname.startsWith(AppConstants.publicServerHostname)) continue;
      if (_isLocalPeer(n.peerId)) continue;
      rx += n.rxBytes;
      tx += n.txBytes;
    }

    final now = DateTime.now();
    var rxRate = 0.0;
    var txRate = 0.0;
    final prevRx = _prevTrafficRx;
    final prevTx = _prevTrafficTx;
    final prevAt = _prevTrafficAt;
    if (prevRx != null && prevTx != null && prevAt != null) {
      final dtSec = now.difference(prevAt).inMilliseconds / 1000.0;
      if (dtSec > 0.2) {
        final dRx = rx - prevRx;
        final dTx = tx - prevTx;
        if (dRx > BigInt.zero) {
          rxRate = dRx.toDouble() / dtSec;
        }
        if (dTx > BigInt.zero) {
          txRate = dTx.toDouble() / dtSec;
        }
      }
    }

    _prevTrafficRx = rx;
    _prevTrafficTx = tx;
    _prevTrafficAt = now;

    final next = RoomTrafficStats(
      rxTotalBytes: _bigIntToClampedInt(rx),
      txTotalBytes: _bigIntToClampedInt(tx),
      rxRateBps: rxRate,
      txRateBps: txRate,
    );
    final prev = roomTraffic.value;
    if (prev.rxTotalBytes != next.rxTotalBytes ||
        prev.txTotalBytes != next.txTotalBytes ||
        (prev.rxRateBps - next.rxRateBps).abs() > 0.5 ||
        (prev.txRateBps - next.txRateBps).abs() > 0.5) {
      roomTraffic.value = next;
    }
  }

  int _bigIntToClampedInt(BigInt v) {
    if (v <= BigInt.zero) return 0;
    final max = BigInt.from(1) << 62;
    if (v >= max) return max.toInt();
    return v.toInt();
  }

  /// 成员是否为当前房间房主（管理节点 / 本机会话房主）。
  /// 是否为当前房间房主节点。共享密码模式下客人侧无法可靠识别，仅房主本人标为房主。
  bool isRoomHostPeer(int peerId, {required bool sessionIsHost, required bool isCredentialPeer}) {
    if (sessionIsHost) return _isLocalPeer(peerId);
    return false;
  }

  /// 从节点列表里挑出"本机"的虚拟 IPv4（去掉 CIDR 后缀），找不到返回空串。
  String _resolveMyVirtualIpv4(List<EnhancedNodeInfo> nodes) {
    EnhancedNodeInfo? candidate;
    for (final n in nodes) {
      if (!_isLocalPeer(n.peerId)) continue;
      // 优先选有合法 IPv4 的本机条目；若全都没有，至少返回第一条本机
      if (n.hasValidIpv4) return n.ipv4.split('/').first.trim();
      candidate ??= n;
    }
    if (candidate == null) return '';
    final raw = candidate.ipv4.split('/').first.trim();
    return raw == '0.0.0.0' ? '' : raw;
  }

  /// 连接后长时间无虚拟 IP 时打告警，并带上节点摘要，方便对照内核日志。
  void _trackMissingVirtualIp(String myIp, List<EnhancedNodeInfo> nodes) {
    if (myIp.isNotEmpty) {
      _noIpSince = null;
      _lastNoIpWarnAt = null;
      return;
    }
    _noIpSince ??= DateTime.now();
    final waited = DateTime.now().difference(_noIpSince!);
    if (waited < const Duration(seconds: 8)) return;
    final last = _lastNoIpWarnAt;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 15)) {
      return;
    }
    _lastNoIpWarnAt = DateTime.now();
    final preview = nodes
        .map((n) {
          final ip = n.hasValidIpv4 ? n.ipv4.split('/').first : '-';
          return '${n.peerId}:${n.hostname}:$ip';
        })
        .join(', ');
    appLogger.w(
      '[NodeManagementService] 已连接 ${waited.inSeconds}s 仍无虚拟 IP；'
      'nodes=[$preview]。请对照 [EasyTier] 是否出现 '
      'tun device ready / dhcp ip changed / tun device error',
    );
  }

  /// 把本地持久化的用户名/头像盖到一个本机 [`EnhancedNodeInfo`] 上。
  /// 仅当本地有值时覆盖；本地清空（用户重置头像）也会下沉到 UI 上。
  EnhancedNodeInfo _enrichLocalNode(EnhancedNodeInfo node) {
    final localName = _appSettings.getUsername().trim();
    final localAvatar = _appSettings.getAvatar();
    final localNetwork = GetIt.I.isRegistered<ConnectivityStatusService>()
        ? GetIt.I<ConnectivityStatusService>().current.value.wireValue
        : null;
    final localFirewall = GetIt.I.isRegistered<FirewallService>()
        ? GetIt.I<FirewallService>().firewallWireValue()
        : 'unsupported';
    final meta = <String, dynamic>{
      ...node.metadata,
      'peerOs': ClientRuntimeInfo.operatingSystem,
      'peerOsVersion': ClientRuntimeInfo.operatingSystemVersion,
      'peerAppName': ClientRuntimeInfo.appName,
      'peerAppVersion': ClientRuntimeInfo.appVersion,
      if (localNetwork != null) 'peerNetwork': localNetwork,
      'peerFirewall': localFirewall,
    };
    return node.copyWith(
      customName: localName.isEmpty ? node.customName : localName,
      avatar: localAvatar ?? node.avatar,
      metadata: meta,
    );
  }

  /// 仅比较「在线用户」列表行会用到的字段；不包含 rx/tx、connections 等每秒随流量变化的统计，
  /// 否则永远无法跳过写入，`userNodes` 仍会每秒整表替换。
  bool _sameKvNodeUiSnapshot(KVNodeInfo a, KVNodeInfo b) {
    return a.peerId == b.peerId &&
        a.hostname == b.hostname &&
        a.ipv4 == b.ipv4 &&
        a.ipv6 == b.ipv6 &&
        a.latencyMs.round() == b.latencyMs.round() &&
        (a.lossRate * 10).round() == (b.lossRate * 10).round() &&
        a.hops.length == b.hops.length &&
        a.version == b.version &&
        a.cost == b.cost &&
        a.remoteStaticPubkeyB64 == b.remoteStaticPubkeyB64 &&
        a.isCredentialPeer == b.isCredentialPeer;
  }

  bool _bytesEqualNullable(Uint8List? a, Uint8List? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == null && b == null;
    return listEquals(a, b);
  }

  bool _sameEnhancedPollSnapshot(EnhancedNodeInfo a, EnhancedNodeInfo b) {
    return _sameKvNodeUiSnapshot(a.baseInfo, b.baseInfo) &&
        mapEquals(a.metadata, b.metadata) &&
        a.customName == b.customName &&
        _bytesEqualNullable(a.avatar, b.avatar);
  }

  bool _sameUserNodesUiSnapshot(
    List<EnhancedNodeInfo> prev,
    List<EnhancedNodeInfo> next,
  ) {
    if (prev.length != next.length) return false;
    for (var i = 0; i < prev.length; i++) {
      if (prev[i].peerId != next[i].peerId) return false;
      if (!_sameEnhancedPollSnapshot(prev[i], next[i])) return false;
    }
    return true;
  }

  bool _isPublicServerNode(EnhancedNodeInfo node) {
    // 公共服务器节点不一定有可直连的虚拟网 IP（可能为空/0.0.0.0），
    // 且其用途是“中转/目录”，不需要进行 user.getInfo / user.update 探测。
    return node.hostname.startsWith(AppConstants.publicServerHostname);
  }

  bool _needsPeerClientEnv(EnhancedNodeInfo n) {
    final ov = n.peerOsVersion;
    final av = n.peerAppVersion;
    final nw = n.peerNetwork;
    final fw = n.peerFirewall;
    final needsFirewall = n.peerOs?.toLowerCase() == 'windows' &&
        (fw == null || fw.isEmpty);
    return ov == null ||
        ov.isEmpty ||
        av == null ||
        av.isEmpty ||
        nw == null ||
        nw.isEmpty ||
        needsFirewall;
  }

  /// 节流后的 `user.getInfo`：缺少客户端环境字段时较快重试，否则低频刷新昵称/头像。
  void _maybeFetchNodeInfo(EnhancedNodeInfo n) {
    if (_isPublicServerNode(n)) return;
    if (_isLocalPeer(n.peerId)) return;

    final client = GetIt.I<PeerRpcClient>();
    if (!client.isBound) return;

    final cooldown =
        _needsPeerClientEnv(n) ? _peerInfoCooldownMissingEnv : _peerInfoCooldownHasEnv;
    final now = DateTime.now();
    final last = _peerInfoFetchStartedAt[n.peerId];
    if (last != null && now.difference(last) < cooldown) return;

    _peerInfoFetchStartedAt[n.peerId] = now;
    unawaited(_fetchNodeInfo(n));
  }

  /// 获取节点信息（头像和昵称）
  ///
  /// 走 peer-RPC 的 `user.getInfo` channel，路由由 EasyTier 负责，调用方只需要
  /// 知道目标节点的 `peerId`。
  Future<void> _fetchNodeInfo(EnhancedNodeInfo node) async {
    if (_isPublicServerNode(node)) return;

    if (node.peerId == _localSyntheticPeerId) return;
    if (_myPeerId != null && node.peerId == _myPeerId) return;

    final client = GetIt.I<PeerRpcClient>();
    if (!client.isBound) return;

    try {
      final knownHash = node.peerAvatarHash;
      final result = await client.call(
        node.peerId,
        'user.getInfo',
        params: {
          if (knownHash != null) 'avatarHash': knownHash,
        },
      );

      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        final name = map['name'] as String?;
        final avatarHash = avatarHashFromParams(map);
        final hasAvatarField = map['avatar'] != null;
        final avatarBytes = hasAvatarField
            ? base64Decode(map['avatar'] as String)
            : null;
        final clearAvatar =
            !hasAvatarField && (avatarHash == null || avatarHash.isEmpty);

        final meta = <String, dynamic>{
          if (map['os'] != null) 'peerOs': map['os'],
          if (map['osVersion'] != null) 'peerOsVersion': map['osVersion'],
          if (map['appName'] != null) 'peerAppName': map['appName'],
          if (map['appVersion'] != null) 'peerAppVersion': map['appVersion'],
          if (map['network'] != null) 'peerNetwork': map['network'],
          if (map['firewall'] != null) 'peerFirewall': map['firewall'],
          'avatarHash': avatarHash ?? '',
        };

        if (name != null ||
            avatarBytes != null ||
            clearAvatar ||
            meta.isNotEmpty) {
          _updateNodeInfo(
            node.peerId,
            name: name,
            avatar: avatarBytes,
            clearAvatar: clearAvatar,
            metadataPatch: meta,
          );
        }
      }
    } on RpcException catch (e) {
      if (e.code == -1 ||
          e.code == -2 ||
          e.code == -32000 ||
          e.code == -32603) {
        if (_verbosePollLogs) {
          appLogger.d(
            '[NodeManagementService] 拉取节点信息失败(忽略) peer=${node.peerId} code=${e.code}: ${e.message}',
          );
        }
        return;
      }
      appLogger.w(
        '[NodeManagementService] 获取节点信息失败 peer=${node.peerId} code=${e.code}: ${e.message}',
      );
    } catch (e) {
      appLogger.e('[NodeManagementService] 获取节点信息异常 peer=${node.peerId}: $e');
    }
  }

  /// 批量更新节点信息（头像和/或昵称），单次 signal 触发
  void _updateNodeInfo(
    int peerId, {
    String? name,
    Uint8List? avatar,
    bool clearAvatar = false,
    Map<String, dynamic>? metadataPatch,
  }) {
    final list = userNodes.value;
    EnhancedNodeInfo? before;
    for (final n in list) {
      if (n.peerId == peerId) {
        before = n;
        break;
      }
    }
    if (before == null) return;

    final mergedMeta = {
      ...before.metadata,
      if (metadataPatch != null) ...metadataPatch,
    };
    final merged = before.copyWith(
      customName: name ?? before.customName,
      avatar: avatar,
      clearAvatar: clearAvatar,
      metadata: mergedMeta,
    );
    if (_sameEnhancedPollSnapshot(before, merged)) return;

    userNodes.value = list.map((n) {
      if (n.peerId != peerId) return n;
      return merged;
    }).toList();
  }

  /// 初始化用户信息
  ///
  /// 从持久化存储加载用户名和头像
  void initUserInfo() {
    currentUsername.value = _appSettings.getUsername();
    final avatar = _appSettings.getAvatar();
    if (avatar != null) {
      currentUserAvatar.value = avatar;
    }
    appLogger.d('[NodeManagementService] 用户信息已初始化: ${currentUsername.value}');
  }

  /// 设置运行状态
  void setRunning(String instanceId) {
    start(instanceId);
  }

  /// 设置停止状态
  void setStopped() {
    stop();
  }

  /// 更新当前用户头像
  Future<void> updateCurrentUserAvatar(Uint8List? avatar) async {
    currentUserAvatar.value = avatar;
    if (avatar != null) {
      await _appSettings.setAvatar(avatar);
      appLogger.d('[NodeManagementService] 用户头像已更新');
    } else {
      await _appSettings.clearAvatar();
      appLogger.d('[NodeManagementService] 用户头像已清除');
    }
    _refreshLocalNodesFromSettings();
  }

  /// 更新当前用户名
  Future<void> updateCurrentUsername(String username) async {
    currentUsername.value = username;
    await _appSettings.setUsername(username);
    appLogger.d('[NodeManagementService] 用户名已更新: $username');
    _refreshLocalNodesFromSettings();
  }

  /// 把最新的本地用户名/头像同步到 [`userNodes`] 列表里的本机条目，省得等下一次
  /// 1 秒轮询才在 UI 上看到变更。
  void _refreshLocalNodesFromSettings() {
    _refreshLocalEnvInUserList();
  }

  /// 释放资源
  void dispose() {
    stop();
    appLogger.d('[NodeManagementService] 资源已释放');
  }
}