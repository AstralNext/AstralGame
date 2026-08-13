import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:astral_game/utils/room_share.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_core.dart';

/// 监听 https://next.astral.fan/j?c=… / astralgame:// 深链，交给 UI 自动进房。
class JoinLinkService {
  final pendingToken = signal<String?>(null);

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _uriSub;
  StreamSubscription<FileSystemEvent>? _fileSub;
  Timer? _filePoll;
  String? _lastFileToken;

  static String get windowsPendingPath {
    final tmp = Platform.environment['TEMP'] ??
        Platform.environment['TMP'] ??
        Directory.systemTemp.path;
    return p.join(tmp, 'astral_game_pending_uri.txt');
  }

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
    if (Platform.isWindows) {
      _watchWindowsPendingFile();
    }
  }

  void dispose() {
    unawaited(_uriSub?.cancel());
    _uriSub = null;
    unawaited(_fileSub?.cancel());
    _fileSub = null;
    _filePoll?.cancel();
    _filePoll = null;
  }

  void consume() => pendingToken.value = null;

  void _considerUri(Uri? uri) {
    if (uri == null) return;
    final token = tokenFromJoinUri(uri) ?? extractJoinToken(uri.toString());
    _emit(token);
  }

  void _emit(String? token) {
    final t = (token ?? '').trim();
    if (t.isEmpty) return;
    if (extractJoinToken(t) == null &&
        !looksLikeShortCode(t) &&
        !looksLikeOfflineInvite(t)) {
      return;
    }
    pendingToken.value = extractJoinToken(t) ?? t;
    appLogger.i('[JoinLink] 待加入 ${pendingToken.value}');
  }

  void _watchWindowsPendingFile() {
    final file = File(windowsPendingPath);
    unawaited(_readPendingFile(file));
    try {
      _fileSub = file.parent.watch(events: FileSystemEvent.all).listen((ev) {
        if (p.basename(ev.path) != p.basename(file.path)) return;
        unawaited(_readPendingFile(file));
      });
    } catch (_) {
      _filePoll = Timer.periodic(const Duration(milliseconds: 800), (_) {
        unawaited(_readPendingFile(file));
      });
    }
  }

  Future<void> _readPendingFile(File file) async {
    try {
      if (!await file.exists()) return;
      final raw = (await file.readAsString()).trim();
      if (raw.isEmpty || raw == _lastFileToken) return;
      _lastFileToken = raw;
      try {
        await file.delete();
      } catch (_) {}
      _emit(extractJoinToken(raw) ?? raw);
    } catch (e) {
      appLogger.d('[JoinLink] 读 pending uri 失败: $e');
    }
  }
}
