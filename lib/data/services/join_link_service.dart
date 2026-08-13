import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:astral_game/config/home_widget_uris.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:signals/signals_core.dart';

/// 用 app_links 监听 `astralgame://` 与 https://next.astral.fan/j（全平台）。
/// 小组件深链 `astralgame://widget/...` 由 [HomeWidgetLaunchHandler] 处理。
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

  void consume() {
    pendingToken.value = null;
    _lastRaw = null;
  }

  void _considerUri(Uri? uri) {
    if (uri == null) return;
    if (uri.scheme.toLowerCase() == kJoinAppScheme &&
        uri.host.toLowerCase() == HomeWidgetUris.host) {
      return;
    }
    _considerRaw(uri.toString());
  }

  void _considerRaw(String raw) {
    final s = raw.trim();
    if (s.isEmpty || s == _lastRaw) return;
    final token = extractJoinToken(s);
    if (token == null) return;
    _lastRaw = s;
    pendingToken.value = token;
    appLogger.i('[JoinLink] 待加入 $token');
  }
}
