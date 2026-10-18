import 'dart:async';
import 'dart:convert';

import 'package:astral_game/config/network_constants.dart';
import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/services/remote_service_exception.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 短码服务返回的一条短码（含作废用的管理令牌）。
typedef ShareCode = ({String code, String adminToken, String expiresAt});

/// 短码服务异常：保持独立类型，供 UI 精确捕获并给出「短码服务暂不可用」类提示。
///
/// [transient] 标记瞬时故障（超时/网络错误/5xx），计入熔断计数；
/// 429/404 等业务应答说明服务本身存活，不计入。
class ShareCodeException extends RemoteServiceException {
  ShareCodeException(super.message, {super.statusCode, this.transient = false});

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

  /// 本地短码缓存（跨启动持久化）：房间指纹 → 最近一次签发的短码。
  static const String _cachePrefsKey = 'astral.share_codes.v1';
  static const int _cacheLimit = 32;

  final Map<String, _CachedCode> _cachedCodes = {};
  Future<void>? _cacheLoading;
  final Map<String, Future<ShareCode>> _pendingCreates = {};

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

  Future<ShareCode> create(RoomInvitePayload payload) {
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

  /// 同一房间（networkName + networkSecret）优先复用仍在用的短码，失效才新建。
  ///
  /// 短码服务本身按请求逐条签发，客户端靠本地缓存（跨启动持久化）补上复用：
  /// 命中缓存时先用一次 GET 确认码还有效且指向同一房间——
  /// - 404（过期/被房主作废）→ 丢掉缓存、重新创建；
  /// - 网络/5xx → 直接抛错，调用方回退离线邀请（此刻也创建不了新码）。
  ///
  /// 并发的同房间请求共享同一个 Future，避免连点生成多条短码。
  Future<ShareCode> createOrReuse(RoomInvitePayload payload) {
    final key = _fingerprint(payload);
    final pending = _pendingCreates[key];
    if (pending != null) return pending;
    final future = _createOrReuse(payload, key);
    _pendingCreates[key] = future;
    return future.whenComplete(() => _pendingCreates.remove(key));
  }

  Future<ShareCode> _createOrReuse(
    RoomInvitePayload payload,
    String key,
  ) async {
    await _ensureCacheLoaded();
    final cached = _cachedCodes[key];
    if (cached != null) {
      if (cached.isExpired(_clock())) {
        _cachedCodes.remove(key);
      } else {
        try {
          final remote = await fetch(cached.code);
          if (remote.networkName == payload.networkName &&
              remote.networkSecret == payload.networkSecret) {
            return cached.asResult();
          }
          // 同一短码指向了别的房间（理论上不会发生）：不能复用。
          _cachedCodes.remove(key);
        } on ShareCodeException catch (e) {
          if (e.statusCode == 404) {
            _cachedCodes.remove(key);
          } else if (e.transient) {
            rethrow;
          }
        }
      }
    }

    final created = await create(payload);
    _cachedCodes[key] = _CachedCode(
      code: created.code,
      adminToken: created.adminToken,
      expiresAt: created.expiresAt,
      savedAt: _clock(),
    );
    await _saveCache();
    return created;
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

  /// 心跳续期：房主在房间存续期间定期调用，让服务端把有效期往后推。
  ///
  /// 404 / 403 表示短码已被作废或令牌失效，调用方应停止心跳；
  /// 其余错误（超时/5xx）只记录，下一次心跳继续重试。
  Future<void> heartbeat(String code, String adminToken) {
    return _guard(
      allowWhenOpen: true,
      body: () async {
        final normalized = normalizeShareCode(code);
        final url = _base().resolve('/v1/codes/$normalized/heartbeat');
        final res = await _withTimeout(
          _client.post(url, headers: {'X-Admin-Token': adminToken}),
        );
        if (res.statusCode == 404) {
          await _forgetCode(normalized);
          throw ShareCodeException('短码无效或已过期', statusCode: 404);
        }
        if (res.statusCode == 403) {
          throw ShareCodeException('短码管理令牌失效', statusCode: 403);
        }
        if (res.statusCode == 429) {
          throw ShareCodeException('操作过于频繁', statusCode: 429);
        }
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw ShareCodeException(
            '心跳失败 (${res.statusCode})',
            statusCode: res.statusCode,
            transient: res.statusCode >= 500,
          );
        }
        final expiresAt = _readExpiresAt(res.body);
        if (expiresAt != null) {
          _updateCachedExpiry(normalized, expiresAt);
          await _saveCache();
        }
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
        if (res.statusCode == 204 || res.statusCode == 404) {
          await _forgetCode(code);
          return;
        }
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

  /// 房间指纹：只用 networkName + networkSecret 标识"同一个房间"。
  ///
  /// 哈希后作为缓存键，避免把房间密码明文写进 SharedPreferences。
  String _fingerprint(RoomInvitePayload payload) {
    final input = '${payload.networkName}\u0001${payload.networkSecret}';
    return sha256.convert(utf8.encode(input)).toString().substring(0, 32);
  }

  Future<void> _ensureCacheLoaded() => _cacheLoading ??= _loadCache();

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cachePrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final now = _clock();
      for (final entry in decoded.entries) {
        final cached = _CachedCode.fromJson(entry.value);
        if (cached == null || cached.isExpired(now)) continue;
        _cachedCodes[entry.key] = cached;
      }
    } catch (e) {
      appLogger.w('[ShareCode] 读取本地短码缓存失败: $e');
    }
  }

  Future<void> _saveCache() async {
    try {
      final now = _clock();
      _cachedCodes.removeWhere((_, v) => v.isExpired(now));
      // 超出上限时淘汰最旧的条目，避免 SharedPreferences 无限增长。
      if (_cachedCodes.length > _cacheLimit) {
        final oldest = _cachedCodes.entries.toList()
          ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
        for (final entry in oldest.take(_cachedCodes.length - _cacheLimit)) {
          _cachedCodes.remove(entry.key);
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cachePrefsKey,
        jsonEncode({
          for (final e in _cachedCodes.entries) e.key: e.value.toJson(),
        }),
      );
    } catch (e) {
      appLogger.w('[ShareCode] 保存本地短码缓存失败: $e');
    }
  }

  /// 短码被作废后同步清掉本地缓存，避免下次复用一条死码。
  Future<void> _forgetCode(String code) async {
    final normalized = normalizeShareCode(code);
    final keys = [
      for (final e in _cachedCodes.entries)
        if (e.value.code == normalized) e.key,
    ];
    if (keys.isEmpty) return;
    for (final key in keys) {
      _cachedCodes.remove(key);
    }
    await _saveCache();
  }

  /// 从心跳应答里取新的到期时间；解析失败返回 null（不影响续期结果）。
  String? _readExpiresAt(String body) {
    try {
      final map = jsonDecode(body);
      if (map is Map && map['expires_at'] != null) {
        final value = '${map['expires_at']}';
        return value.isEmpty ? null : value;
      }
    } catch (_) {
      // 心跳应答格式异常时忽略，服务端有效期已经推进，本地缓存下次 GET 会校准。
    }
    return null;
  }

  /// 心跳续期后同步本地缓存的到期时间，避免下次启动误判为过期。
  void _updateCachedExpiry(String code, String expiresAt) {
    for (final entry in _cachedCodes.entries.toList(growable: false)) {
      if (entry.value.code == code) {
        _cachedCodes[entry.key] = entry.value.copyWith(expiresAt: expiresAt);
      }
    }
  }

  void close() => _client.close();
}

/// 本地缓存的短码条目。
class _CachedCode {
  const _CachedCode({
    required this.code,
    required this.adminToken,
    required this.expiresAt,
    required this.savedAt,
  });

  final String code;
  final String adminToken;
  final String expiresAt;
  final DateTime savedAt;

  /// [expiresAt] 为空或不是合法时间时视为"未知"，交给 GET 校验兜底。
  bool isExpired(DateTime now) {
    final at = DateTime.tryParse(expiresAt);
    return at != null && !at.isAfter(now);
  }

  ShareCode asResult() =>
      (code: code, adminToken: adminToken, expiresAt: expiresAt);

  _CachedCode copyWith({String? expiresAt}) => _CachedCode(
    code: code,
    adminToken: adminToken,
    expiresAt: expiresAt ?? this.expiresAt,
    savedAt: savedAt,
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'admin_token': adminToken,
    'expires_at': expiresAt,
    'saved_at': savedAt.toIso8601String(),
  };

  static _CachedCode? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final code = raw['code'];
    if (code is! String || code.isEmpty) return null;
    return _CachedCode(
      code: code,
      adminToken: '${raw['admin_token'] ?? ''}',
      expiresAt: '${raw['expires_at'] ?? ''}',
      savedAt:
          DateTime.tryParse('${raw['saved_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
