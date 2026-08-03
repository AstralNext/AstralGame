import 'dart:convert';
import 'dart:typed_data';

/// 把任意 JSON-able dart 对象编码到 peer rpc 的 `payload` 字节流。
///
/// `null` 会编码为空字节序列，方便 handler 写空 params/空响应（不带 body）。
Uint8List encodeRpcPayload(Object? value) {
  if (value == null) return Uint8List(0);
  return Uint8List.fromList(utf8.encode(jsonEncode(value)));
}

/// [`encodeRpcPayload`] 的反向操作。空 payload → `null`。
///
/// 解析失败会抛 [`FormatException`]；调用方一般可以把异常翻译成
/// `RpcException(-32700, 'Parse error')` 再回包。
dynamic decodeRpcPayload(List<int> bytes) {
  if (bytes.isEmpty) return null;
  return jsonDecode(utf8.decode(bytes));
}
