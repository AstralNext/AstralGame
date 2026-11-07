import 'dart:async';

import 'package:astral_game/src/rust/api/steam.dart' as rust_steam;

/// 全工具统一的基础口令。
///
/// 搜房默认禁止「无门槛房」：即使房主没有设额外密码，也必须带上这串口令才能
/// 完成 HELLO 校验。它不是安全边界（所有客户端都内置），只用来挡住误连。
const String kSteamLobbyBasePassword = 'astral-lobby-basic-v1';

/// 大厅协议版本（对应 Rust `lobby::PROTOCOL_VERSION`）。
const String kSteamLobbyProtocolVersion = '1';

/// 房门槛：只有基础口令。
const String kSteamLobbyGateBasic = 'basic';

/// 房门槛：基础口令 + 房主额外密码。
const String kSteamLobbyGateDouble = 'double';

/// 房门槛：完全公开（必须二次确认）。
const String kSteamLobbyGateOpen = 'open';

/// 拼出 HELLO 用的 join_token。
///
/// `double` 房间要额外密码；放后面是为了让「基础口令不匹配」和「额外密码
/// 不匹配」在房主侧都表现为同一条「房间密码不匹配」，不泄露门槛类型。
String composeSteamJoinToken({String? extraPassword}) {
  final extra = extraPassword?.trim() ?? '';
  if (extra.isEmpty) return kSteamLobbyBasePassword;
  return '$kSteamLobbyBasePassword|$extra';
}

/// Steam(SDR) 组网传输的 Dart 门面。
///
/// Rust 侧负责 Steam 初始化、wintun 虚拟网卡、星型组网转发与应用内 RPC；
/// 这里只做参数组装与「等待就绪」。
class SteamTransportService {
  /// 读取 Steam 状态（首次调用会拉起后台线程并尝试 SteamAPI_Init）。
  Future<rust_steam.SteamStatusInfo> status() => rust_steam.steamStatus();

  /// 读取当前房间成员 / 虚拟 IP。
  Future<rust_steam.SteamRoomInfo> roomInfo() => rust_steam.steamRoomInfo();

  Future<int> myPeerId() => rust_steam.steamMyPeerId();

  /// 等待 Steam 登录 + SDR 就绪。
  ///
  /// 订阅 Rust 侧的状态事件（登录 / 断线 / SDR 回调），不再 500ms 轮询；
  /// 超时后回读一次快照兜底。
  Future<rust_steam.SteamStatusInfo> waitReady({
    Duration timeout = const Duration(seconds: 25),
  }) => awaitSteamReady(
    readStatus: rust_steam.steamStatus,
    subscribeStatus: rust_steam.steamSubscribeStatus,
    timeout: timeout,
  );

  static bool _isReady(rust_steam.SteamStatusInfo status) =>
      status.ok && status.loggedOn && status.relayReady;

  /// 是否已具备组网条件（登录 + SDR 就绪）。
  static bool isReady(rust_steam.SteamStatusInfo status) => _isReady(status);

  /// 把「未就绪」快照翻译成给用户看的原因。
  ///
  /// [waitReady] 超时后返回的是最后一次快照：Steam 仍在初始化时要给出
  /// 「正在连接」而不是「未初始化」，超时后也必须是可理解的具体原因。
  static String describeNotReady(rust_steam.SteamStatusInfo status) {
    final message = status.message.trim();
    if (!status.ok) {
      if (message.isEmpty || message == 'Steam 未初始化') {
        return 'Steam 接口尚未初始化完成（请确认 Steam 客户端已启动并登录）';
      }
      return message;
    }
    if (!status.loggedOn) {
      return '已连接 Steam，但账号尚未登录（请在 Steam 客户端完成登录）';
    }
    return 'Steam 已登录，SDR 中继网络仍在准备';
  }

  /// Steam 客户端都没起来时没必要干等到超时。
  static bool _failedFast(rust_steam.SteamStatusInfo status) =>
      !status.ok && status.message.contains('初始化失败');

  /// 房主：创建 Steam 公开大厅，写入 `ag_*` 标签并开房。
  ///
  /// 返回时大厅已可被同游戏客户端搜到，虚拟网卡也已在监听。
  Future<rust_steam.SteamLobbyInfo> createLobby({
    required String gameId,
    required String name,
    required String gate,
    required int maxMembers,
    required String joinToken,
    required String nickname,
  }) {
    return rust_steam.steamLobbyCreate(
      gameId: gameId,
      name: name,
      gate: gate,
      maxMembers: maxMembers,
      joinToken: joinToken,
      nickname: nickname,
    );
  }

  /// 搜索同游戏的大厅（服务端 `ag_game` 过滤 + 本地二次校验）。
  Future<List<rust_steam.SteamLobbyInfo>> searchLobbies(String gameId) =>
      rust_steam.steamLobbySearch(gameId: gameId);

  /// 加入大厅并连上房主；返回时隧道已可用。
  Future<rust_steam.SteamLobbyInfo> joinLobby({
    required String lobbyId,
    required String gameId,
    required String joinToken,
    required String nickname,
  }) {
    return rust_steam.steamLobbyJoin(
      lobbyId: lobbyId,
      gameId: gameId,
      joinToken: joinToken,
      nickname: nickname,
    );
  }

  /// 诊断：注入一个离线超过宽限期的成员并跑真实 prune（需要调试开关）。
  Future<String> debugGhostProbe() => rust_steam.steamDebugGhostProbe();

  /// 只读大厅元数据（加入后立刻离开）：邀请进房前确认门槛用。
  Future<rust_steam.SteamLobbyInfo> peekLobby(String lobbyId) =>
      rust_steam.steamLobbyPeek(lobbyId: lobbyId);

  /// 离开当前大厅（同时停止隧道）。
  Future<void> leaveLobby() => rust_steam.steamLobbyLeave();

  /// 设置大厅是否可被搜索到。
  Future<void> setJoinable(bool joinable) =>
      rust_steam.steamLobbySetJoinable(joinable: joinable);

  /// 打开 Steam 原生好友邀请界面。
  Future<void> openInviteDialog() => rust_steam.steamLobbyInviteDialog();

  /// 好友从 Steam 点「加入」或应用被 `+connect_lobby` 拉起时的大厅 id。
  Future<String?> pendingInvite() => rust_steam.steamPendingLobbyInvite();

  /// 清空待处理的邀请。
  Future<void> clearPendingInvite() =>
      rust_steam.steamClearPendingLobbyInvite();

  /// 房主：只开隧道、不建大厅（兼容没有大厅信息的旧邀请链）。
  Future<rust_steam.SteamStatusInfo> startHost({
    required String joinToken,
    required String nickname,
    required String gameId,
  }) {
    return rust_steam.steamStart(
      host: true,
      hostSteamId: '',
      joinToken: joinToken,
      nickname: nickname,
      gameId: gameId,
    );
  }

  /// 客机：只连房主 SteamID、不经过大厅。
  Future<rust_steam.SteamStatusInfo> startGuest({
    required String hostSteamId,
    required String joinToken,
    required String nickname,
    required String gameId,
  }) {
    return rust_steam.steamStart(
      host: false,
      hostSteamId: hostSteamId,
      joinToken: joinToken,
      nickname: nickname,
      gameId: gameId,
    );
  }

  Future<void> stop() => rust_steam.steamStop();
}

/// [SteamTransportService.waitReady] 的核心逻辑，抽成纯函数便于单测。
///
/// 先读一次快照；未就绪则订阅状态事件，首个「就绪」或「快速失败」事件
/// 完成等待（只完成一次），超时后回读一次快照兜底并取消订阅。
Future<rust_steam.SteamStatusInfo> awaitSteamReady({
  required Future<rust_steam.SteamStatusInfo> Function() readStatus,
  required Stream<rust_steam.SteamStatusInfo> Function() subscribeStatus,
  Duration timeout = const Duration(seconds: 25),
}) async {
  var last = await readStatus();
  if (_steamStatusReady(last) || _steamStatusFailedFast(last)) return last;

  final completer = Completer<rust_steam.SteamStatusInfo>();
  final sub = subscribeStatus().listen((status) {
    last = status;
    if (!completer.isCompleted &&
        (_steamStatusReady(status) || _steamStatusFailedFast(status))) {
      completer.complete(status);
    }
  }, onError: (Object _) {});
  final timer = Timer(timeout, () async {
    if (completer.isCompleted) return;
    try {
      last = await readStatus();
    } catch (_) {}
    if (!completer.isCompleted) completer.complete(last);
  });
  try {
    return await completer.future;
  } finally {
    timer.cancel();
    // FRB 的 Rust 流是 `async*` + `await for(ReceivePort)`：只有 Rust 侧关闭
    // sink 后 `cancel()` 才会完成。这里不等待它，避免未就绪路径把调用方卡死。
    unawaited(sub.cancel());
  }
}

bool _steamStatusReady(rust_steam.SteamStatusInfo status) =>
    SteamTransportService._isReady(status);

bool _steamStatusFailedFast(rust_steam.SteamStatusInfo status) =>
    SteamTransportService._failedFast(status);
