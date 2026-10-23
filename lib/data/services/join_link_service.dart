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
  final Completer<void> _initialLinkReady = Completer<void>();
  bool _hadInitialLink = false;

  /// 启动时是否由邀请链接拉起。消费 token 后仍保留，供「启动后自动进入房间」
  /// 判断是否需要让路给链接进房逻辑。
  bool get hadInitialLink => _hadInitialLink;

  /// 首次链接探测完成（无论是否找到邀请）。
  Future<void> get initialLinkReady => _initialLinkReady.future;

  Future<void> start() async {
    // 启动参数里已经解析过的原文：Windows/Linux 冷启动会把链接同时交给
    // Dart 参数和 app_links 的 getInitialLink()，这里跳过重复投递。
    final fromLaunchArgs = _lastRaw;
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial == null || initial.toString().trim() != fromLaunchArgs) {
        _considerUri(initial);
      }
      if (pendingToken.value != null) _hadInitialLink = true;
    } catch (e) {
      appLogger.d('[JoinLink] 读取启动链接失败: $e');
    } finally {
      if (!_initialLinkReady.isCompleted) _initialLinkReady.complete();
      // 首次链接已经交给 pendingToken，之后不再需要按原文去重；
      // 否则在应用运行中重复点同一个快捷方式会被当作重复链接丢弃。
      _lastRaw = null;
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
    // 首次链接探测完成前保留原文，避免同一条链接又被 app_links 的
    // getInitialLink() 重复投递（Windows 冷启动链接会同时出现在进程参数里）。
    if (_initialLinkReady.isCompleted) _lastRaw = null;
  }

  /// 从进程启动参数中提取邀请链接。
  ///
  /// Linux 冷启动时 app_links 的 command-line hook 还没注册（插件在窗口创建时
  /// 才注册），拿不到首个链接；这里用 runner 透传的 entrypoint 参数兜底。
  /// Windows 冷启动同样会把链接作为参数传入，会与 app_links 的结果按原文去重。
  void considerLaunchArguments(List<String> args) {
    for (final arg in args) {
      if (arg.startsWith('-')) continue;
      _considerRaw(arg);
    }
    if (pendingToken.value != null) _hadInitialLink = true;
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
