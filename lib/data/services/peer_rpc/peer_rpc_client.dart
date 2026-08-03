import 'dart:async';

import 'package:astral_game/utils/logger.dart';
import 'package:astral_rust_core/p2p_service.dart';

import 'peer_rpc_codec.dart';
import 'peer_rpc_exception.dart';

/// 替代旧 `NodeNetClient` 的 peer-RPC 客户端封装。
class PeerRpcClient {
  PeerRpcClient(this._p2p);

  final P2PService _p2p;

  /// 默认 RPC 超时。和旧实现保持一致。
  static const Duration defaultTimeout = Duration(seconds: 5);

  /// 是否打印调用成功日志。频繁场景下默认关闭。
  static const bool _verboseLog = false;

  String? _instanceId;

  /// 是否已经绑定到一个运行中的 instance。
  bool get isBound => _instanceId != null;

  /// 绑定/解绑当前 instance。传 `null` 解绑。
  void bindInstance(String? instanceId) {
    _instanceId = (instanceId == null || instanceId.isEmpty) ? null : instanceId;
  }

  /// 释放资源（兼容旧 `dispose()` 接口）。
  void dispose() {
    _instanceId = null;
  }

  /// 发送请求-响应 RPC，等待对端 handler 回包。
  Future<dynamic> call(
    int peerId,
    String channel, {
    dynamic params,
    Duration timeout = defaultTimeout,
  }) async {
    final id = _ensureBound();
    final sw = Stopwatch()..start();

    final AppCallResultC result;
    try {
      result = await _p2p.appCall(
        instanceId: id,
        dstPeerId: peerId,
        channel: channel,
        requestId: BigInt.zero,
        payload: encodeRpcPayload(params),
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
    } catch (_) {
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
    final id = _ensureBound();
    try {
      await _p2p.appNotify(
        instanceId: id,
        dstPeerId: peerId,
        channel: channel,
        payload: encodeRpcPayload(params),
        timeoutMs: timeout.inMilliseconds,
      );
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
  Future<int> ping(
    int peerId, {
    Duration timeout = defaultTimeout,
  }) async {
    final id = _ensureBound();
    try {
      final rtt = await _p2p.peerPing(
        instanceId: id,
        dstPeerId: peerId,
        timeoutMs: timeout.inMilliseconds,
      );
      return rtt.toInt();
    } catch (e) {
      throw RpcException(-32603, 'ping error: $e');
    }
  }

  String _ensureBound() {
    final id = _instanceId;
    if (id == null) {
      throw RpcException(
        -32002,
        'PeerRpcClient is not bound to any instance (call bindInstance first)',
      );
    }
    return id;
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
