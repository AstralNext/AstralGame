import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 头像内容 hash；无头像返回 null。
String? avatarContentHash(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  return sha256.convert(bytes).toString();
}

/// RPC 参数里的 `avatarHash`。
String? avatarHashFromParams(dynamic params) {
  if (params is! Map) return null;
  final raw = params['avatarHash'];
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}

/// 对端已知 hash 与当前不一致时才回传整图。
bool shouldSendAvatarBytes(String? knownHash, String? currentHash) {
  if (currentHash == null || currentHash.isEmpty) return false;
  return (knownHash ?? '').trim() != currentHash;
}
