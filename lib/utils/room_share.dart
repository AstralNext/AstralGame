import 'dart:convert';

import 'package:astral_game/data/models/active_room_session.dart';

/// 离线邀请前缀（Base64url 载荷），与 9 位短码互斥。
const String kOfflineInvitePrefix = 'AG1.';

String roomShareCodeForClipboard(String code) => code.trim();

bool looksLikeShortCode(String raw) =>
    RegExp(r'^\d{9}$').hasMatch(raw.trim());

bool looksLikeOfflineInvite(String raw) {
  final t = raw.trim();
  if (t.startsWith(kOfflineInvitePrefix)) return true;
  // 兼容误复制：整段像 Base64 且能解出 JSON
  return t.length > 40 && RegExp(r'^[A-Za-z0-9_\-+/=]+$').hasMatch(t);
}

/// 将邀请载荷编码为可粘贴的离线串（无需短码服务器）。
String encodeOfflineInvite(RoomInvitePayload payload) {
  final json = jsonEncode(payload.toJson());
  final b64 = base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  return '$kOfflineInvitePrefix$b64';
}

/// 解析离线邀请；失败返回 null。
RoomInvitePayload? tryDecodeOfflineInvite(String raw) {
  try {
    return decodeOfflineInvite(raw);
  } catch (_) {
    return null;
  }
}

RoomInvitePayload decodeOfflineInvite(String raw) {
  var text = raw.trim();
  if (text.startsWith(kOfflineInvitePrefix)) {
    text = text.substring(kOfflineInvitePrefix.length).trim();
  }
  text = text.replaceAll(RegExp(r'\s+'), '');
  // 补齐 Base64url padding
  final mod = text.length % 4;
  if (mod > 0) {
    text = text.padRight(text.length + (4 - mod), '=');
  }
  final bytes = base64Url.decode(text);
  final map = jsonDecode(utf8.decode(bytes));
  if (map is! Map<String, dynamic>) {
    throw FormatException('离线邀请不是 JSON 对象');
  }
  final payload = RoomInvitePayload.fromJson(map);
  if (payload.networkName.isEmpty) {
    throw FormatException('离线邀请缺少 network_name');
  }
  if (payload.networkSecret.isEmpty) {
    throw FormatException('离线邀请缺少房间密码');
  }
  return payload;
}
