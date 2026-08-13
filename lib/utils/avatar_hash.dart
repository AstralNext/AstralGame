import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 头像内容 hash；无头像返回 null。
String? avatarContentHash(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  return sha256.convert(bytes).toString();
}

/// 对端已知 hash 与当前不一致时才回传整图。
bool shouldSendAvatarBytes(String? knownHash, String? currentHash) {
  if (currentHash == null || currentHash.isEmpty) return false;
  return (knownHash ?? '').trim() != currentHash;
}
