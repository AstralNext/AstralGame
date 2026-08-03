/// 跨节点 RPC 异常。
///
/// 状态码语义（与 EasyTier 的 `astral_app_rpc::status` + 历史 JSON-RPC 错误码兼容）：
/// - `0`：成功（约定不会以异常形式抛出）。
/// - `> 0`：业务自定义错误（沿用旧 JSON-RPC 风格的 `-32xxx` 值的正数化版本，
///   或者业务自己定义；具体语义由 channel 的两端约定）。
/// - `< 0`：传输/框架级错误，由底层注入：
///   - `-1` 对端没有订阅入站事件（`NO_SUBSCRIBER`）。
///   - `-2` 对端业务超时未回复（`REPLY_TIMEOUT`）。
///   - `-3` 对端服务在回复前被销毁（`SERVICE_DROPPED`）。
///   - `-32000` 客户端等待响应超时（本端发起方超时）。
///   - `-32601` 收到了未注册的 channel。
///   - `-32603` 收端 handler 抛出了非 [`RpcException`] 类型的异常。
class RpcException implements Exception {
  final int code;
  final String message;
  final dynamic data;

  RpcException(this.code, this.message, {this.data});

  @override
  String toString() => 'RpcException($code): $message';
}
