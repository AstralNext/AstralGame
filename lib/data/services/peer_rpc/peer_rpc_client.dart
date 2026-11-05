import 'dart:async';

import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/src/rust/api/p2p.dart';
import 'package:astral_game/src/rust/api/steam.dart' as rust_steam;
import 'package:astral_game/src/rust/api/pear.dart' as rust_pear;

import 'peer_rpc_codec.dart';
import 'peer_rpc_exception.dart';

/// 替代旧 `NodeNetClient` 的 peer-RPC 客户端封装。
///
/// 后端有三种：EasyTier 实例（按 instanceId）、Steam 组网房间或
/// Holepunch Pear 组网房间（都没有 instanceId）。
class PeerRpcClient {
  PeerRpcClient();

  /// 默认 RPC 超时。和旧实现保持一致。
  static const Duration defaultTimeout = Duration(seconds: 5);

  /// 是否打印调用成功日志。频繁场景下默认关闭。
  static const bool _verboseLog = false;

  String? _instanceId;
  bool _steam = false;
  bool _pear = false;

  /// 是否已经绑定到一个运行中的实例 / Steam / Pear 房间。
  bool get isBound => _steam || _pear || _instanceId != null;

  /// 绑定/解绑当前 EasyTier instance。传 `null` 解绑。
  void bindInstance(String? instanceId) {
    _steam = false;
    _pear = false;
    _instanceId = (instanceId == null || instanceId.isEmpty)
        ? null
        : instanceId;
  }

  /// 绑定到 Steam 组网房间（没有 EasyTier instanceId）。
  void bindSteam() {
    _instanceId = null;
    _steam = true;
    _pear = false;
  }

  /// 绑定到 Holepunch Pear 组网房间（没有 EasyTier instanceId）。
  void bindPear() {
    _instanceId = null;
    _steam = false;
    _pear = true;
  }

  /// 释放资源（兼容旧 `dispose()` 接口）。
  void dispose() {
    _instanceId = null;
    _steam = false;
    _pear = false;
  }

  /// 发送请求-响应 RPC，等待对端 handler 回包。
  Future<dynamic> call(
    int peerId,
    String channel, {
    dynamic params,
    Duration timeout = defaultTimeout,
  }) async {
    _ensureBound();
    final sw = Stopwatch()..start();

    final AppCallResultC result;
    try {
      final payload = encodeRpcPayload(params);
      result = _steam
          ? await rust_steam.steamAppCall(
              dstPeerId: peerId,
              channel: channel,
              requestId: BigInt.zero,
              payload: payload,
              flags: 0,
              timeoutMs: timeout.inMilliseconds,
            )
          : _pear
          ? await rust_pear.pearAppCall(
              dstPeerId: peerId,
              channel: channel,
              requestId: BigInt.zero,
              payload: payload,
              flags: 0,
              timeoutMs: timeout.inMilliseconds,
            )
          : await appCall(
              instanceId: _instanceId!,
              dstPeerId: peerId,
              channel: channel,
              requestId: BigInt.zero,
              payload: payload,
              flags: 0,
              timeoutMs: timeout.inMilliseconds,
            );
    } on TimeoutException {
      throw RpcException(-32000, 'Request timeout');
    } catch (e) {
      final msg = e.toString();
      if (_looksLikeTimeout(msg)) {
        throw RpcException(-32000, 'Request timeout: $msg');
      }
      throw RpcException(-32603, 'Internal error: $e');
    }

    if (_verboseLog) {
      appLogger.d(
        '[PeerRpcClient] <- $channel peer=$peerId status=${result.status} costMs=${sw.elapsedMilliseconds}',
      );
    }

    if (result.status == 0) {
      try {
        return decodeRpcPayload(result.payload);
      } catch (e) {
        throw RpcException(-32700, 'Parse response error: $e');
      }
    }

    final dynamic data;
    try {
      data = decodeRpcPayload(result.payload);
    } catch (e) {
      appLogger.w('[PeerRpcClient] 操作失败', error: e);
      throw RpcException(result.status, _resolveErrorMsg(result));
    }
    throw RpcException(result.status, _resolveErrorMsg(result), data: data);
  }

  /// 发送 fire-and-forget 通知。
  Future<void> notify(
    int peerId,
    String channel, {
    dynamic params,
    Duration timeout = defaultTimeout,
  }) async {
    _ensureBound();
    try {
      final payload = encodeRpcPayload(params);
      if (_steam) {
        await rust_steam.steamAppNotify(
          dstPeerId: peerId,
          channel: channel,
          payload: payload,
        );
      } else if (_pear) {
        await rust_pear.pearAppNotify(
          dstPeerId: peerId,
          channel: channel,
          payload: payload,
        );
      } else {
        await appNotify(
          instanceId: _instanceId!,
          dstPeerId: peerId,
          channel: channel,
          payload: payload,
          timeoutMs: timeout.inMilliseconds,
        );
      }
    } on TimeoutException {
      throw RpcException(-32000, 'Request timeout');
    } catch (e) {
      appLogger.w(
        '[PeerRpcClient] notify 失败 channel=$channel peer=$peerId err=$e',
      );
      rethrow;
    }
  }

  /// peer-to-peer ping（RTT 毫秒）。
  Future<int> ping(int peerId, {Duration timeout = defaultTimeout}) async {
    _ensureBound();
    try {
      final rtt = _steam
          ? await rust_steam.steamPeerPing(
              dstPeerId: peerId,
              timeoutMs: timeout.inMilliseconds,
            )
          : _pear
          ? await rust_pear.pearPeerPing(
              dstPeerId: peerId,
              timeoutMs: timeout.inMilliseconds,
            )
          : await peerPing(
              instanceId: _instanceId!,
              dstPeerId: peerId,
              timeoutMs: timeout.inMilliseconds,
            );
      return rtt.toInt();
    } catch (e) {
      throw RpcException(-32603, 'ping error: $e');
    }
  }

  void _ensureBound() {
    if (!isBound) {
      throw RpcException(
        -32002,
        'PeerRpcClient is not bound (call bindInstance / bindSteam / bindPear first)',
      );
    }
  }

  bool _looksLikeTimeout(String message) {
    final m = message.toLowerCase();
    return m.contains('timeout') ||
        m.contains('timed out') ||
        m.contains('deadline');
  }

  String _resolveErrorMsg(AppCallResultC result) {
    if (result.errorMsg.isNotEmpty) return result.errorMsg;
    switch (result.status) {
      case -1:
        return 'No subscriber on receiver';
      case -2:
        return 'Receiver application reply timeout';
      case -3:
        return 'Receiver service dropped before reply';
      default:
        return 'rpc status=${result.status}';
    }
  }
}
