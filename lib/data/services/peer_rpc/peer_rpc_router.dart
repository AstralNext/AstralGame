import 'dart:async';
import 'dart:typed_data';

import 'package:astral_game/utils/logger.dart';
import 'package:astral_rust_core/p2p_service.dart';

import 'peer_rpc_codec.dart';
import 'peer_rpc_exception.dart';

/// 入站 channel 的 handler 类型。`params` 是 [`decodeRpcPayload`] 解出的 JSON 值
/// （null / Map / List / num / String / bool）。返回值会经 [`encodeRpcPayload`]
/// 编回 payload 发给调用方；如果是 notify 调用，返回值会被忽略。
typedef MethodHandler = FutureOr<dynamic> Function(dynamic params);

/// 入站 notify 监听器：每条收到的通知都会回调一遍。
typedef NotificationListener = void Function(
  String channel,
  dynamic params,
  int fromPeerId,
);

/// 替代旧 `NodeNetServer` 的 peer-RPC 路由器。
class PeerRpcRouter {
  PeerRpcRouter(this._p2p);

  final P2PService _p2p;
  final Map<String, MethodHandler> _methods = {};
  final List<NotificationListener> _notificationListeners = [];

  // ignore: cancel_subscriptions
  StreamSubscription<AppInboundEventC>? _inboundSub;
  String? _instanceId;

  /// 是否打印每个入站事件的概览。频繁场景下默认关闭，避免刷屏。
  static const bool _accessLog = false;

  bool get isRunning => _instanceId != null;
  String? get instanceId => _instanceId;
  int get methodsCount => _methods.length;

  /// 注册单个方法。重复注册会覆盖。
  void register(String channel, MethodHandler handler) {
    _methods[channel] = handler;
    appLogger.d('[PeerRpcRouter] 注册方法: $channel');
  }

  /// 批量注册方法。
  void registerAll(Map<String, MethodHandler> methods) {
    _methods.addAll(methods);
    appLogger.d('[PeerRpcRouter] 批量注册 ${methods.length} 个方法');
  }

  /// 添加 notify 监听器（不区分 channel）。
  void addNotificationListener(NotificationListener listener) {
    _notificationListeners.add(listener);
  }

  /// 绑定到指定的 EasyTier instance 并开始监听入站事件。
  Future<void> start(String instanceId) async {
    if (_instanceId != null) {
      await stop();
    }
    _instanceId = instanceId;

    final stream = _p2p.subscribeAppInbound(instanceId);
    _inboundSub = stream.listen(
      _onEvent,
      onError: (Object err, StackTrace st) {
        appLogger.e(
          '[PeerRpcRouter] 入站流错误 instance=$instanceId: $err',
          error: err,
          stackTrace: st,
        );
      },
      onDone: () {
        if (_instanceId == instanceId) {
          _instanceId = null;
          _inboundSub = null;
          appLogger.d('[PeerRpcRouter] 入站流已关闭 instance=$instanceId');
        }
      },
    );

    appLogger.d(
      '[PeerRpcRouter] 已启动 instance=$instanceId methods=$methodsCount',
    );
  }

  /// 停止监听并清理状态。
  Future<void> stop() async {
    final sub = _inboundSub;
    final id = _instanceId;
    _inboundSub = null;
    _instanceId = null;
    await sub?.cancel();
    if (id != null) {
      appLogger.d('[PeerRpcRouter] 已停止 instance=$id');
    }
  }

  Future<void> _onEvent(AppInboundEventC evt) async {
    final channel = evt.channel;
    dynamic params;
    try {
      params = decodeRpcPayload(evt.payload);
    } catch (e) {
      appLogger.w('[PeerRpcRouter] payload 解析失败 channel=$channel from=${evt.fromPeerId}: $e');
      if (evt.kind == AppInboundKindC.call) {
        await _safeReply(evt.token, -32700, 'Parse error', null);
      }
      return;
    }

    if (_accessLog) {
      final kind = evt.kind == AppInboundKindC.call ? 'call' : 'notify';
      appLogger.d(
        '[PeerRpcRouter] <- $kind channel=$channel from=${evt.fromPeerId}',
      );
    }

    if (evt.kind == AppInboundKindC.notify) {
      await _dispatchNotify(channel, params, evt.fromPeerId);
      return;
    }

    await _dispatchCall(channel, params, evt.token);
  }

  Future<void> _dispatchNotify(
    String channel,
    dynamic params,
    int fromPeerId,
  ) async {
    final handler = _methods[channel];
    if (handler != null) {
      try {
        await handler(params);
      } catch (e, st) {
        // notify 没有回包通道，handler 异常只能记录。
        appLogger.e(
          '[PeerRpcRouter] notify handler 异常 channel=$channel: $e',
          error: e,
          stackTrace: st,
        );
      }
    }
    for (final l in _notificationListeners) {
      try {
        l(channel, params, fromPeerId);
      } catch (e) {
        appLogger.w('[PeerRpcRouter] notify listener 抛错: $e');
      }
    }
  }

  Future<void> _dispatchCall(
    String channel,
    dynamic params,
    BigInt token,
  ) async {
    final handler = _methods[channel];
    if (handler == null) {
      appLogger.w('[PeerRpcRouter] 未注册的 channel: $channel');
      await _safeReply(token, -32601, 'Method not found', channel);
      return;
    }
    try {
      final result = await handler(params);
      await _safeReply(token, 0, '', result);
    } on RpcException catch (e) {
      // 业务异常：保留 code（一般 > 0），data 走 payload。
      await _safeReply(token, e.code, e.message, e.data);
    } catch (e, st) {
      appLogger.e(
        '[PeerRpcRouter] handler 内部错误 channel=$channel: $e',
        error: e,
        stackTrace: st,
      );
      await _safeReply(token, -32603, 'Internal error: $e', null);
    }
  }

  Future<void> _safeReply(
    BigInt token,
    int status,
    String errorMsg,
    Object? data,
  ) async {
    final id = _instanceId;
    if (id == null) return;
    final Uint8List payload;
    try {
      payload = encodeRpcPayload(data);
    } catch (e) {
      // 编码出错就降级为空 payload + 错误信息。
      appLogger.w('[PeerRpcRouter] 回包编码失败 token=$token: $e');
      try {
        await _p2p.appCallReply(
          instanceId: id,
          token: token,
          status: -32603,
          errorMsg: 'Encode error: $e',
          payload: Uint8List(0),
        );
      } catch (_) {}
      return;
    }
    try {
      await _p2p.appCallReply(
        instanceId: id,
        token: token,
        status: status,
        errorMsg: errorMsg,
        payload: payload,
      );
    } catch (e) {
      appLogger.w('[PeerRpcRouter] 回包失败 token=$token: $e');
    }
  }
}
