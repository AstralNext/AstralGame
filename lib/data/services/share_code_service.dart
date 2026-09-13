import 'dart:async';
import 'dart:convert';

import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/services/remote_service_exception.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:http/http.dart' as http;

/// 短码服务异常：保持独立类型，供 UI 精确捕获并给出「短码服务暂不可用」类提示。
///
/// [transient] 标记瞬时故障（超时/网络错误/5xx），计入熔断计数；
/// 429/404 等业务应答说明服务本身存活，不计入。
class ShareCodeException extends RemoteServiceException {
  ShareCodeException(
    super.message, {
    super.statusCode,
    this.transient = false,
  });

  final bool transient;
}

/// astral-share 客户端（地址内置，不可配置）。
///
/// 内置熔断：连续 [breakerThreshold] 次瞬时故障后短路 [breakerCooldown]。
/// 短路期间 create/revoke 直接抛错（调用方均有回退：离线邀请/作废失败仅记日志）；
/// fetch 仍放行——用户显式输入短码加入是核心动作，不能被熔断挡住，
/// 但其成败同样计入计数，服务恢复后熔断自然关闭。
class ShareCodeService {
  ShareCodeService({http.Client? client, DateTime Function()? clock})
    : _client = client ?? http.Client(),
      _clock = clock ?? DateTime.now;

  /// 内置短码服务。
  static const String baseUrl = kShareCodeServiceBaseUrl;

  /// 连续瞬时故障达到该次数即熔断。
  static const int breakerThreshold = 3;

  /// 熔断冷却：期间短路 create/revoke，到期后半开放行一次真实请求。
  static const Duration breakerCooldown = Duration(seconds: 60);

  final http.Client _client;
  final DateTime Function() _clock;

  int _consecutiveTransientFailures = 0;
  DateTime? _breakerOpenedAt;

  Uri _base() {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse(base);
  }

  bool get _breakerOpen {
    final openedAt = _breakerOpenedAt;
    if (openedAt == null) return false;
    return _clock().difference(openedAt) < breakerCooldown;
  }

  void _onTransientFailure() {
    _consecutiveTransientFailures++;
    if (_consecutiveTransientFailures >= breakerThreshold) {
      final wasOpen = _breakerOpen;
      _breakerOpenedAt = _clock();
      if (!wasOpen) {
        appLogger.w(
          '[ShareCode] 连续 $breakerThreshold 次瞬时失败，'
          '熔断 ${breakerCooldown.inSeconds}s',
        );
      }
    }
  }

  void _onSuccess() {
    _consecutiveTransientFailures = 0;
    _breakerOpenedAt = null;
  }

  /// 熔断守卫：开路且不允许放行时直接抛错；否则执行请求并按成败更新计数。
  Future<T> _guard<T>({
    required bool allowWhenOpen,
    required Future<T> Function() body,
  }) async {
    if (_breakerOpen && !allowWhenOpen) {
      throw ShareCodeException('服务连续失败，稍后自动重试', transient: true);
    }
    try {
      final result = await body();
      _onSuccess();
      return result;
    } on ShareCodeException catch (e) {
      if (e.transient) _onTransientFailure();
      rethrow;
    } on http.ClientException catch (e) {
      _onTransientFailure();
      throw ShareCodeException('短码服务无法连接: $e', transient: true);
    }
  }

  /// 统一超时包装：超时抛 [ShareCodeException]（瞬时故障），保持异常契约一致。
  Future<T> _withTimeout<T>(Future<T> future) async {
    try {
      return await future.timeout(kShareCodeTimeout);
    } on TimeoutException {
      throw ShareCodeException('短码服务超时', transient: true);
    }
  }

  Future<({String code, String adminToken, String expiresAt})> create(
    RoomInvitePayload payload,
  ) {
    return _guard(
      allowWhenOpen: false,
      body: () async {
        final url = _base().resolve('/v1/codes');
        final res = await _withTimeout(
          _client.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload.toJson()),
          ),
        );
        if (res.statusCode == 429) {
          throw ShareCodeException('创建过于频繁，请稍后再试', statusCode: 429);
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw ShareCodeException(
            '短码服务错误 (${res.statusCode})',
            statusCode: res.statusCode,
            transient: res.statusCode >= 500,
          );
        }
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        return (
          code: '${map['code']}',
          adminToken: '${map['admin_token']}',
          expiresAt: '${map['expires_at'] ?? ''}',
        );
      },
    );
  }

  Future<RoomInvitePayload> fetch(String code) {
    return _guard(
      allowWhenOpen: true,
      body: () async {
        final normalized = normalizeShareCode(code);
        if (!looksLikeShortCode(normalized)) {
          throw ShareCodeException('请输入 6 位短码');
        }
        final url = _base().resolve('/v1/codes/$normalized');
        final res = await _withTimeout(_client.get(url));
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
            transient: res.statusCode >= 500,
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
      },
    );
  }

  Future<void> revoke(String code, String adminToken) {
    return _guard(
      allowWhenOpen: false,
      body: () async {
        final url = _base().resolve('/v1/codes/${normalizeShareCode(code)}');
        final res = await _withTimeout(
          _client.delete(url, headers: {'X-Admin-Token': adminToken}),
        );
        if (res.statusCode == 204 || res.statusCode == 404) return;
        if (res.statusCode == 429) {
          throw ShareCodeException('操作过于频繁', statusCode: 429);
        }
        throw ShareCodeException(
          '作废失败 (${res.statusCode})',
          statusCode: res.statusCode,
        );
      },
    );
  }

  void close() => _client.close();
}
