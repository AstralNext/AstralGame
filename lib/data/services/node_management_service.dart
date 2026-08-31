import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:signals/signals_core.dart';
import 'package:astral_game/utils/avatar_hash.dart';
import 'package:astral_game/utils/client_runtime_info.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:astral_game/config/constants.dart';
import 'package:astral_rust_core/p2p_service.dart';

import '../models/enhanced_node_info.dart';
import '../models/local_self_nodes.dart';
import '../models/peer_link_metrics.dart';
import 'app_settings_service.dart';
import 'connectivity_status_service.dart';
import 'firewall_service.dart';
import 'isp_info_service.dart';
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
NodeManagementService({
required P2PService p2pService,
required AppSettingsService appSettings,
required PeerRpcClient peerRpc,
ConnectivityStatusService? connectivity,
FirewallService? firewall,
IspInfoService? ispInfo,
})  : _p2pService = p2pService,
_appSettings = appSettings,
_peerRpc = peerRpc,
_connectivity = connectivity,
_firewall = firewall,
_ispInfo = ispInfo;

final P2PService _p2pService;
final AppSettingsService _appSettings;
final PeerRpcClient _peerRpc;
final ConnectivityStatusService? _connectivity;
final FirewallService? _firewall;
final IspInfoService? _ispInfo;

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

/// 本机的虚拟网 IPv4（不带 CIDR）。由规范化后的本机哨兵行推导，
/// 与成员列表同一数据源，避免左右栏 IP 状态分叉。
final myVirtualIpv4 = signal<String>('');

final Map<int, Signal<PeerLinkMetrics>> _linkMetrics = {};

Timer? _pollingTimer;
int _pollTick = 0;
/// 已连接但尚未拿到虚拟 IP 时，节流告警，避免每秒刷屏。
DateTime? _noIpSince;
DateTime? _lastNoIpWarnAt;

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

bool _pollInFlight = false;
int _pollGeneration = 0;
/// 防止 `_refreshLocalEnvInUserList` 用过期快照盖掉正在写入的 poll 结果。
int _nodesEpoch = 0;

/// 稳态轮询：成员进出可接受约 2s 延迟；未拿到虚拟 IP 时更快探。
static const Duration _pollingInterval = Duration(seconds: 2);
static const Duration _pollingIntervalUntilIp = Duration(milliseconds: 500);

/// 未拿到虚拟 IP 时 500ms，否则 2s。
static Duration pollDelayFor({required bool hasVirtualIp}) {
return hasVirtualIp ? _pollingInterval : _pollingIntervalUntilIp;
}

String? get instanceId => currentInstanceId.value;
bool get isRunning => currentInstanceId.value != null;

/// 该 peer 的时延/丢包（独立 signal，成员行可局部 Watch）。
Signal<PeerLinkMetrics> linkMetricsOf(int peerId) {
return _linkMetrics.putIfAbsent(
peerId,
() => signal(PeerLinkMetrics.zero),
);
}

/// 与仪表盘「在线用户」列表一致（含本机，排除公共服务器节点）。
List<EnhancedNodeInfo> get onlinePeersForDisplay {
return userNodes.value
.where((n) => !n.hostname.startsWith(AppConstants.publicServerHostname))
.toList();
}

/// 启动节点管理
void start(String instanceId) {
_myPeerId = null;
_noIpSince = DateTime.now();
_lastNoIpWarnAt = null;
_nodesEpoch++;
_clearLinkMetrics();
myVirtualIpv4.value = '';
// 先放入本机占位行再标记 running，避免窄屏成员列表先闪骨架。
userNodes.value = [
_enrichLocalNode(localSelfPlaceholder(hostname: _localHostname())),
];
currentInstanceId.value = instanceId;
_bindEnvListeners();
if (RuntimePlatform.isWindows && _firewall != null) {
unawaited(_firewall.refreshPrivateProfile());
_firewallRefreshTimer?.cancel();
_firewallRefreshTimer = Timer.periodic(
const Duration(seconds: 15),
(_) {
if (currentInstanceId.value == null) return;
unawaited(_firewall.refreshPrivateProfile());
},
);
}
// 立刻轮询；peer_id 并行去拉。合并重复本机行由 collapseLocalSelfNodes 负责，
// 不再把「列表能不能显示自己」卡在 myPeerId RPC 上。
_startPolling(instanceId);
unawaited(_refreshMyPeerIdThenCollapse(instanceId));
appLogger.i('[NodeManagementService] 已启动，实例ID: $instanceId');
}

Future<void> _refreshMyPeerIdThenCollapse(String instanceId) async {
await _refreshMyPeerId(instanceId);
if (currentInstanceId.value != instanceId) return;
_collapseUserNodesInPlace();
}

void _collapseUserNodesInPlace() {
final prev = userNodes.value;
final collapsed = collapseLocalSelfNodes(
prev,
isLocalPeer: _isLocalPeer,
).map((n) {
if (!_isLocalPeer(n.peerId)) return n;
return _enrichLocalNode(n);
}).toList();
if (!sameUserNodesUiSnapshot(prev, collapsed)) {
userNodes.value = collapsed;
}
}

String _localHostname() {
try {
final name = Platform.localHostname.trim();
if (name.isNotEmpty) return name;
} catch (e) { appLogger.w('[NodeMgmt] 操作失败', error: e); }
return 'local';
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
_clearLinkMetrics();
myVirtualIpv4.value = '';
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
final gen = _pollGeneration;
unawaited(_pollThenRearm(instanceId, gen));
}

Duration _pollDelay() {
return pollDelayFor(hasVirtualIp: myVirtualIpv4.value.isNotEmpty);
}

Future<void> _pollThenRearm(String instanceId, int gen) async {
await _pollNetworkStatus(instanceId);
if (gen != _pollGeneration) return;
if (currentInstanceId.value != instanceId) return;
_pollingTimer?.cancel();
_pollingTimer = Timer(_pollDelay(), () {
if (gen != _pollGeneration) return;
if (_verbosePollLogs) {
_pollTick++;
appLogger.d('[NodeManagementService] poll tick=$_pollTick');
}
unawaited(_pollThenRearm(instanceId, gen));
});
}

/// 停止轮询
void _stopPolling() {
_pollGeneration++;
_pollingTimer?.cancel();
_pollingTimer = null;
}

void _bindEnvListeners() {
_unbindEnvListeners();
final connectivity = _connectivity;
if (connectivity != null) {
_envListenerDisposers.add(effect(() {
connectivity.current.value;
_onVolatileEnvChanged();
}));
}
final firewall = _firewall;
if (firewall != null) {
_envListenerDisposers.add(effect(() {
firewall.privateProfileEnabled.value;
_onVolatileEnvChanged();
}));
}
final ispInfo = _ispInfo;
if (ispInfo != null) {
_envListenerDisposers.add(effect(() {
ispInfo.label.value;
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
final epoch = _nodesEpoch;
final nodes = userNodes.value;
if (nodes.isEmpty) return;
final updated = nodes.map((n) {
if (!_isLocalPeer(n.peerId)) return n;
return _enrichLocalNode(n);
}).toList();
if (epoch != _nodesEpoch) return;
if (!sameUserNodesUiSnapshot(nodes, updated)) {
userNodes.value = updated;
}
}

/// 轮询网络状态
///
/// 获取最新的网络状态和节点信息。内部按职责拆分为若干子方法，避免
/// 一个方法里叠满 7 层逻辑，改一处就容易碰坏别的分支。
Future<void> _pollNetworkStatus(String instanceId) async {
if (_pollInFlight) return;
_pollInFlight = true;
try {
if (currentInstanceId.value != instanceId) return;
final status = await _p2pService.getNetworkStatus(instanceId);
_updateNetworkStatusSignal(status);

final prevUsers = userNodes.value;
final normalized = _buildNormalizedNodes(
prev: prevUsers,
rawNodes: status.nodes,
);
final collapsed = _collapseAndEnsureSelf(
normalized,
prevSnapshot: prevUsers,
);

_cleanupStalePeerFetchTimers(collapsed);
final myIp = _extractOwnVirtualIp(collapsed);

final published = _commitNodesSignal(
prevUsers: prevUsers,
newNodes: collapsed,
);
_updateVirtualIpSignal(myIp, nodes: collapsed);
_trackMissingVirtualIp(myIp, published);

if (_verbosePollLogs) {
  final total = (status.totalNodes).toInt();
  _verboseLogPublishedNodes(published, totalRaw: total);
}

// 拉取对端资料（昵称/头像/客户端环境）：节流，避免每秒打一遍 RPC。
for (final n in published) {
_maybeFetchNodeInfo(n);
}
} catch (e, stackTrace) {
appLogger.e('[NodeManagementService] 轮询网络状态失败: $e', error: e, stackTrace: stackTrace);
} finally {
_pollInFlight = false;
}
}

/// 仅在 Rust 侧快照确有变化时更新 [`networkStatus`] signal，避免其它监听者
/// 无意义每秒重建。
void _updateNetworkStatusSignal(dynamic status) {
final nsTotal = status.totalNodes;
final nextNetworkStatus = KVNetworkStatus(
totalNodes: nsTotal is BigInt ? nsTotal : BigInt.from(nsTotal),
nodes: List<KVNodeInfo>.from(status.nodes as List),
);
final prevNs = networkStatus.value;
if (prevNs == null || prevNs != nextNetworkStatus) {
networkStatus.value = nextNetworkStatus;
}
}

/// 把 EasyTier 返回的原始节点列表转成规范化 [`EnhancedNodeInfo`] Map，
/// 去重、过滤公共服务器、合并旧的 metadata 与头像、对本机条目本地填充。
Map<int, EnhancedNodeInfo> _buildNormalizedNodes({
required List<EnhancedNodeInfo> prev,
required List<KVNodeInfo> rawNodes,
}) {
final currentNodes = Map<int, EnhancedNodeInfo>.fromEntries(
prev.map((node) => MapEntry(node.peerId, node)),
);
final newNodes = <int, EnhancedNodeInfo>{};
for (final node in rawNodes) {
// 公共服务器仅用于中继/目录，不应出现在"在线用户"列表。
if (node.hostname.startsWith(AppConstants.publicServerHostname)) continue;
final prevNode = currentNodes[node.peerId];
var enhanced = EnhancedNodeInfo(
baseInfo: node,
// 合并 RPC 写入的 metadata（含 peerOsVersion 等），否则下一轮 poll 会清空，
// UI 上表现为版本行「闪一下又没了」。
metadata: {...?prevNode?.metadata},
customName: prevNode?.customName,
avatar: prevNode?.avatar,
);
// 本机条目（合成哨兵 peer_id=0 或真实本机 peer_id）直接用本地资料填充，
// 不走 RPC：自己问自己没意义，而且能保证 UI 列表里"自己"始终最新。
if (_isLocalPeer(node.peerId)) {
enhanced = _enrichLocalNode(enhanced);
}
newNodes[node.peerId] = enhanced;
}
return newNodes;
}

/// 合并 peer_id=0 哨兵与真实本机 peer，并确保至少有一条本机占位行，
/// 避免 UI 在首次联上网前的空轮询里显示"没有任何成员"。
List<EnhancedNodeInfo> _collapseAndEnsureSelf(
Map<int, EnhancedNodeInfo> normalizedMap, {
required List<EnhancedNodeInfo> prevSnapshot,
}) {
final normalized = normalizedMap.values.toList()
..sort((a, b) => a.peerId.compareTo(b.peerId));
final collapsed = collapseLocalSelfNodes(
normalized,
isLocalPeer: _isLocalPeer,
).map((n) {
if (!_isLocalPeer(n.peerId)) return n;
return _enrichLocalNode(n);
}).toList();
return ensureLocalSelfPresent(
collapsed,
prevSnapshot,
isLocalPeer: _isLocalPeer,
fallback: _enrichLocalNode(
localSelfPlaceholder(hostname: _localHostname()),
),
);
}

/// 清理不再在线的节点对应的 RPC 资料拉取节流计时。
void _cleanupStalePeerFetchTimers(List<EnhancedNodeInfo> published) {
final activePeerIds = published.map((n) => n.peerId).toSet();
_peerInfoFetchStartedAt.removeWhere((id, _) => !activePeerIds.contains(id));
}

String _extractOwnVirtualIp(List<EnhancedNodeInfo> published) {
return virtualIpv4FromNodes(published, isLocalPeer: _isLocalPeer) ?? '';
}

/// 对比新旧列表，真正发生 UI 层面可见变化时才提交到 [`userNodes`] signal，
/// 避免每秒 setValue 造成的监听侧无意义重建。使用 [`_nodesEpoch`] 版本锁，
/// 防止轮询间隔重叠时"旧结果覆盖新结果"。
List<EnhancedNodeInfo> _commitNodesSignal({
required List<EnhancedNodeInfo> prevUsers,
required List<EnhancedNodeInfo> newNodes,
}) {
_nodesEpoch++;
final epoch = _nodesEpoch;
_syncLinkMetrics(newNodes, prune: false);
if (!sameUserNodesUiSnapshot(prevUsers, newNodes)) {
if (epoch == _nodesEpoch) {
userNodes.value = newNodes;
}
}
_pruneLinkMetrics(newNodes);
return newNodes;
}

/// 更新本机虚拟 IP signal，并在 IP 首次出现或发生变化时记录日志。
void _updateVirtualIpSignal(String myIp, {required List<EnhancedNodeInfo> nodes}) {
if (nodes.isEmpty && myIp.isEmpty) return;
if (myIp == myVirtualIpv4.value) return;
final prev = myVirtualIpv4.value;
myVirtualIpv4.value = myIp;
appLogger.i(
'[NodeManagementService] 本机虚拟 IP: '
'${prev.isEmpty ? '(空)' : prev} -> ${myIp.isEmpty ? '(空)' : myIp}',
);
}

void _verboseLogPublishedNodes(List<EnhancedNodeInfo> published, {required int totalRaw}) {
final nodesPreview = published
.map((n) => '${n.peerId}:${n.hostname}:${n.ipv4.split('/').first}')
.join(', ');
appLogger.d(
'[NodeManagementService] poll users(total=${published.length}, rawTotal=$totalRaw) [$nodesPreview]',
);
}

/// 判断给定 peer_id 是否对应"本机"（合成哨兵或真实本机）。
bool _isLocalPeer(int peerId) =>
peerId == _localSyntheticPeerId ||
(_myPeerId != null && peerId == _myPeerId);

/// 是否为本机节点（含 Rust 合成本机哨兵 id）。
bool isLocalPeer(int peerId) => _isLocalPeer(peerId);

/// 成员是否为当前房间房主（管理节点 / 本机会话房主）。
/// 是否为当前房间房主节点。共享密码模式下客人侧无法可靠识别，仅房主本人标为房主。
bool isRoomHostPeer(int peerId, {required bool sessionIsHost, required bool isCredentialPeer}) {
if (sessionIsHost) return _isLocalPeer(peerId);
return false;
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
final localNetwork = _connectivity?.current.value.wireValue;
final localFirewall = _firewall?.firewallWireValue() ?? 'unsupported';
final localIsp = _ispInfo?.label.value;
final meta = <String, dynamic>{
...node.metadata,
'peerOs': ClientRuntimeInfo.operatingSystem,
'peerOsVersion': ClientRuntimeInfo.operatingSystemVersion,
'peerAppName': ClientRuntimeInfo.appName,
'peerAppVersion': ClientRuntimeInfo.appVersion,
'peerNetwork': ?localNetwork,
'peerFirewall': localFirewall,
if (localIsp != null && localIsp.isNotEmpty) 'peerIsp': localIsp,
};
return node.copyWith(
customName: localName.isEmpty ? node.customName : localName,
avatar: localAvatar ?? node.avatar,
metadata: meta,
);
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

// ================= 节点资料拉取（peer RPC `user.getInfo`） =================
//
// 本节与上面的轮询主流程共享 userNodes signal 与本机身份判定（_isLocalPeer 等），
// 因此不拆成独立 Service——拆出反而需要回绑 5 个依赖，耦合更高。
// 对外仅通过 [_maybeFetchNodeInfo] 进入（由轮询规范化时调用）。

/// 节流后的 `user.getInfo`：缺少客户端环境字段时较快重试，否则低频刷新昵称/头像。
void _maybeFetchNodeInfo(EnhancedNodeInfo n) {
if (_isPublicServerNode(n)) return;
if (_isLocalPeer(n.peerId)) return;

if (!_peerRpc.isBound) return;

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

if (!_peerRpc.isBound) return;

try {
final knownHash = node.peerAvatarHash;
final result = await _peerRpc.call(
node.peerId,
'user.getInfo',
params: {
'avatarHash': ?knownHash,
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
if (map['isp'] != null && (map['isp'] as String).isNotEmpty)
'peerIsp': map['isp'],
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
...?metadataPatch,
};
final merged = before.copyWith(
customName: name ?? before.customName,
avatar: avatar,
clearAvatar: clearAvatar,
metadata: mergedMeta,
);
if (sameEnhancedPollSnapshot(before, merged)) return;

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

void _syncLinkMetrics(List<EnhancedNodeInfo> nodes, {bool prune = true}) {
final live = <int>{};
for (final n in nodes) {
live.add(n.peerId);
final next = PeerLinkMetrics(
latencyMs: n.baseInfo.latencyMs,
lossRate: n.baseInfo.lossRate,
);
final existing = _linkMetrics[n.peerId];
if (existing == null) {
_linkMetrics[n.peerId] = signal(next);
continue;
}
if (existing.value.visiblyDiffersFrom(next)) {
existing.value = next;
}
}
if (prune) {
_pruneLinkMetrics(nodes);
}
}

void _pruneLinkMetrics(List<EnhancedNodeInfo> nodes) {
final live = {for (final n in nodes) n.peerId};
final staleIds = [
for (final id in _linkMetrics.keys)
if (!live.contains(id)) id,
];
for (final id in staleIds) {
_linkMetrics.remove(id)?.dispose();
}
}

void _clearLinkMetrics() {
for (final s in _linkMetrics.values) {
s.dispose();
}
_linkMetrics.clear();
}

/// 释放资源
void dispose() {
stop();
appLogger.d('[NodeManagementService] 资源已释放');
}
}
