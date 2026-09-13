import 'dart:async';

/// 远程 HTTP 服务异常基类：统一各服务的失败语义。
///
/// 调用方可精确捕获具体子类（如 [ShareCodeException]），
/// 也可统一捕获本基类对远程失败做一族处理。
class RemoteServiceException implements Exception {
  RemoteServiceException(this.message, {this.statusCode});

  /// 面向用户的错误描述（中文，已含服务名上下文）。
  final String message;

  /// HTTP 状态码；非 HTTP 原因（解析失败、超时等）时为 null。
  final int? statusCode;

  @override
  String toString() => message;
}

/// 远程请求统一超时包装：超时转 [RemoteServiceException]，
/// 避免裸 [TimeoutException] 逃出服务层破坏统一异常契约。
Future<T> withRemoteTimeout<T>(
  Future<T> future,
  Duration timeout,
  String label,
) async {
  try {
    return await future.timeout(timeout);
  } on TimeoutException {
    throw RemoteServiceException('$label超时');
  }
}
