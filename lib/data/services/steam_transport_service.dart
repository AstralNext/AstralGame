import 'dart:async';

import 'package:astral_game/src/rust/api/steam.dart' as rust_steam;

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
  }) async {
    var last = await rust_steam.steamStatus();
    if (_isReady(last) || _failedFast(last)) return last;

    final completer = Completer<rust_steam.SteamStatusInfo>();
    final sub = rust_steam.steamSubscribeStatus().listen((status) {
      last = status;
      if (!completer.isCompleted &&
          (_isReady(status) || _failedFast(status))) {
        completer.complete(status);
      }
    }, onError: (Object _) {});
    final timer = Timer(timeout, () async {
      if (completer.isCompleted) return;
      try {
        last = await rust_steam.steamStatus();
      } catch (_) {}
      if (!completer.isCompleted) completer.complete(last);
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  static bool _isReady(rust_steam.SteamStatusInfo status) =>
      status.ok && status.loggedOn && status.relayReady;

  /// Steam 客户端都没起来时没必要干等到超时。
  static bool _failedFast(rust_steam.SteamStatusInfo status) =>
      !status.ok && status.message.contains('初始化失败');

  /// 房主：建立虚拟网卡并等待成员加入。
  Future<rust_steam.SteamStatusInfo> startHost({
    required String joinToken,
    required String nickname,
  }) {
    return rust_steam.steamStart(
      host: true,
      hostSteamId: '',
      joinToken: joinToken,
      nickname: nickname,
    );
  }

  /// 客机：连到房主 SteamID 并加入同一虚拟局域网。
  Future<rust_steam.SteamStatusInfo> startGuest({
    required String hostSteamId,
    required String joinToken,
    required String nickname,
  }) {
    return rust_steam.steamStart(
      host: false,
      hostSteamId: hostSteamId,
      joinToken: joinToken,
      nickname: nickname,
    );
  }

  Future<void> stop() => rust_steam.steamStop();
}
