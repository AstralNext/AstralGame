import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:signals/signals_core.dart';

/// 用 app_links 监听 `astralgame://` 与 https://next.astral.fan/j（全平台）。
class JoinLinkService {
  final pendingToken = signal<String?>(null);

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _uriSub;
  String? _lastRaw;

  Future<void> start() async {
    try {
      final initial = await _appLinks.getInitialLink();
      _considerUri(initial);
    } catch (e) {
      appLogger.d('[JoinLink] 读取启动链接失败: $e');
    }
    _uriSub = _appLinks.uriLinkStream.listen(
      _considerUri,
      onError: (e) => appLogger.d('[JoinLink] 链接流错误: $e'),
    );
  }

  void dispose() {
    unawaited(_uriSub?.cancel());
    _uriSub = null;
  }

  void consume() => pendingToken.value = null;

  void _considerUri(Uri? uri) {
    if (uri == null) return;
    _considerRaw(uri.toString());
  }

  void _considerRaw(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty || s == _lastRaw) return;
    _lastRaw = s;
    _emit(extractJoinToken(s) ?? s);
  }

  void _emit(String? token) {
    final t = (token ?? '').trim();
    if (t.isEmpty) return;
    final extracted = extractJoinToken(t);
    if (extracted == null &&
        !looksLikeShortCode(t) &&
        !looksLikeOfflineInvite(t)) {
      return;
    }
    pendingToken.value = extracted ?? t;
    appLogger.i('[JoinLink] 待加入 ${pendingToken.value}');
  }
}
