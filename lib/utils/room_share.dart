import 'dart:convert';

import 'package:astral_game/data/models/active_room_session.dart';

/// 离线邀请前缀（Base64url 载荷），与 9 位短码互斥。
const String kOfflineInvitePrefix = 'AG1.';

const String kJoinHttpsHost = 'next.astral.fan';
const String kJoinLegacyHttpsHost = 'astral.fan';
const String kJoinHttpsPath = '/j';
const String kJoinAppScheme = 'astralgame';

bool looksLikeShortCode(String raw) =>
    RegExp(r'^\d{9}$').hasMatch(raw.trim());

bool looksLikeOfflineInvite(String raw) {
  final t = raw.trim();
  if (t.startsWith(kOfflineInvitePrefix)) return true;
  return t.length > 40 && RegExp(r'^[A-Za-z0-9_\-+/=]+$').hasMatch(t);
}

bool looksLikeJoinToken(String raw) =>
    looksLikeShortCode(raw) || looksLikeOfflineInvite(raw);

bool isJoinHttpsHost(String host) {
  final h = host.toLowerCase();
  return h == kJoinHttpsHost ||
      h == 'www.$kJoinHttpsHost' ||
      h == kJoinLegacyHttpsHost ||
      h == 'www.$kJoinLegacyHttpsHost';
}

/// 统一邀请链接：有短码用短码，否则用离线码。各平台同一条 URL。
String buildJoinShareUrl({String? shortCode, String? offlineInvite}) {
  final token = preferredJoinToken(
    shortCode: shortCode,
    offlineInvite: offlineInvite,
  );
  if (token == null) return '';
  return Uri(
    scheme: 'https',
    host: kJoinHttpsHost,
    path: kJoinHttpsPath,
    queryParameters: {'c': token},
  ).toString();
}

/// 历史分享码 → 统一邀请链接（短码或离线码均可）。
String joinShareUrlFromCode(String code) {
  final t = code.trim();
  if (t.isEmpty) return '';
  return buildJoinShareUrl(shortCode: t, offlineInvite: t);
}

String? preferredJoinToken({String? shortCode, String? offlineInvite}) {
  final code = (shortCode ?? '').trim();
  if (looksLikeShortCode(code)) return code;
  final offline = (offlineInvite ?? '').trim();
  if (offline.isNotEmpty) return offline;
  if (code.isNotEmpty) return code;
  return null;
}

String joinShareMessage(String url, {String? gameName}) {
  final name = (gameName ?? '').trim();
  if (name.isEmpty) return 'Astral Game 房间邀请\n$url';
  return '一起来玩 $name\n$url';
}

/// 从链接 / 自定义协议 / 短码 / 离线码里取出进房 token。
String? extractJoinToken(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  text = text.replaceAll(RegExp(r'^["<\s]+|["\s>]+$'), '').trim();

  final uri = Uri.tryParse(text);
  if (uri != null && uri.hasScheme) {
    final fromUri = tokenFromJoinUri(uri);
    if (fromUri != null) return fromUri;
  }

  final embedded = RegExp(
    r'https?://(?:www\.)?(?:next\.)?astral\.fan/j[^\s]*',
    caseSensitive: false,
  ).firstMatch(text);
  if (embedded != null) {
    final u = Uri.tryParse(embedded.group(0)!);
    if (u != null) {
      final t = tokenFromJoinUri(u);
      if (t != null) return t;
    }
  }

  if (looksLikeJoinToken(text)) return text;
  return null;
}

String? tokenFromJoinUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  String? fromQueryOrFragment() {
    final c = uri.queryParameters['c'] ?? uri.queryParameters['code'];
    final q = (c ?? '').trim();
    if (q.isNotEmpty) return q;
    final f = uri.fragment.trim();
    if (f.isEmpty) return null;
    return Uri.decodeComponent(f);
  }

  if (scheme == kJoinAppScheme || scheme == 'astral') {
    if (host == 'widget') return null;
    final query = fromQueryOrFragment();
    if (query != null) return query;
    if (host == 'j' || host == 'join') {
      if (segs.isNotEmpty) return Uri.decodeComponent(segs.first);
    }
    if (segs.isNotEmpty && (segs.first == 'j' || segs.first == 'join')) {
      if (segs.length >= 2) return Uri.decodeComponent(segs[1]);
    }
    return null;
  }

  if ((scheme == 'http' || scheme == 'https') && isJoinHttpsHost(host)) {
    final query = fromQueryOrFragment();
    if (query != null) return query;
    if (segs.isNotEmpty && segs.first == 'j' && segs.length >= 2) {
      return Uri.decodeComponent(segs.sublist(1).join('/'));
    }
  }
  return null;
}

/// 将邀请载荷编码为可粘贴的离线串（无需短码服务器）。
String encodeOfflineInvite(RoomInvitePayload payload) {
  final json = jsonEncode(payload.toJson());
  final b64 = base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  return '$kOfflineInvitePrefix$b64';
}

RoomInvitePayload decodeOfflineInvite(String raw) {
  var text = raw.trim();
  if (text.startsWith(kOfflineInvitePrefix)) {
    text = text.substring(kOfflineInvitePrefix.length).trim();
  }
  text = text.replaceAll(RegExp(r'\s+'), '');
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
