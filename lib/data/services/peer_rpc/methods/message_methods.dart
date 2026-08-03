import 'package:astral_game/data/services/peer_rpc/peer_rpc_router.dart';

/// Peer 消息 RPC 占位（无 UI 订阅；保留 handler 避免对端调用报 unknown method）。
class MessageMethods {
  void send(dynamic params) {}

  void broadcast(dynamic params) => send(params);

  Map<String, MethodHandler> get methods => {
        'message.send': send,
        'message.broadcast': broadcast,
      };
}
