import 'package:astral_game/utils/room_share.dart';

/// Android 桌面小部件点击深链（与 Kotlin [WidgetClickHelper] 约定一致）。
abstract final class HomeWidgetUris {
  static const scheme = kJoinAppScheme;
  static const host = 'widget';

  static const pathConnect = '/connect';
  static const pathRooms = '/rooms';
  static const pathMembers = '/members';
  static const pathRefresh = '/refresh';

  static Uri connect() => Uri(scheme: scheme, host: host, path: pathConnect);

  static Uri rooms({String? roomCode, int? roomId}) => Uri(
        scheme: scheme,
        host: host,
        path: pathRooms,
        queryParameters: {
          if (roomCode != null && roomCode.isNotEmpty) 'code': roomCode,
          if (roomId != null) 'id': '$roomId',
        },
      );

  static Uri members() => Uri(scheme: scheme, host: host, path: pathMembers);

  static Uri refresh() => Uri(scheme: scheme, host: host, path: pathRefresh);
}
