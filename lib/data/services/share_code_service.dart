import 'dart:convert';

import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:http/http.dart' as http;

class ShareCodeException implements Exception {
  ShareCodeException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// astral-share 客户端（地址内置，不可配置）。
class ShareCodeService {
  ShareCodeService();

  /// 内置短码服务。
  static const String baseUrl = 'http://103.194.107.25:8080/';

  final http.Client _client = http.Client();

  Uri _base() {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse(base);
  }

  Future<({String code, String adminToken, String expiresAt})> create(
    RoomInvitePayload payload,
  ) async {
    final url = _base().resolve('/v1/codes');
    final res = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload.toJson()),
    );
    if (res.statusCode == 429) {
      throw ShareCodeException('创建过于频繁，请稍后再试', statusCode: 429);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ShareCodeException(
        '短码服务错误 (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      code: '${map['code']}',
      adminToken: '${map['admin_token']}',
      expiresAt: '${map['expires_at'] ?? ''}',
    );
  }

  Future<RoomInvitePayload> fetch(String code) async {
    final normalized = normalizeShareCode(code);
    if (!looksLikeShortCode(normalized)) {
      throw ShareCodeException('请输入 6 位短码');
    }
    final url = _base().resolve('/v1/codes/$normalized');
    final res = await _client.get(url);
    if (res.statusCode == 429) {
      throw ShareCodeException('查询过于频繁，请稍后再试', statusCode: 429);
    }
    if (res.statusCode == 404) {
      throw ShareCodeException('短码无效或已过期', statusCode: 404);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ShareCodeException(
        '短码服务错误 (${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = RoomInvitePayload.fromJson(map);
    if (payload.networkName.isEmpty) {
      throw ShareCodeException('短码载荷不完整');
    }
    if (payload.networkSecret.isEmpty) {
      throw ShareCodeException('短码载荷不完整（缺少房间密码）');
    }
    return payload;
  }

  Future<void> revoke(String code, String adminToken) async {
    final url = _base().resolve('/v1/codes/${normalizeShareCode(code)}');
    final res = await _client.delete(
      url,
      headers: {'X-Admin-Token': adminToken},
    );
    if (res.statusCode == 204 || res.statusCode == 404) return;
    if (res.statusCode == 429) {
      throw ShareCodeException('操作过于频繁', statusCode: 429);
    }
    throw ShareCodeException('作废失败 (${res.statusCode})', statusCode: res.statusCode);
  }
}
