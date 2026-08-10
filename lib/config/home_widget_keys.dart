/// 桌面小部件 SharedPreferences 键名与 Android Provider 类名。
abstract final class HomeWidgetKeys {
  // 快捷连接
  static const connectRoomLabel = 'connect_room_label';
  static const connectRoomCode = 'connect_room_code';
  static const connectStatus = 'connect_status';
  /// Machine-readable: `connected` / `disconnected` (avoid comparing Chinese in Kotlin).
  static const connectStatusCode = 'connect_status_code';
  static const connectHint = 'connect_hint';

  // 房间列表（JSON 数组，最多 4 条）
  static const roomsJson = 'rooms_json';
  static const roomsSummary = 'rooms_summary';

  // 在线成员
  static const membersCount = 'members_count';
  static const membersCountText = 'members_count_text';
  static const membersPreview = 'members_preview';
  static const membersRoomLabel = 'members_room_label';

  /// 与 [AppThemePalette] 同步的 ARGB 色值。
  static const themeCard = 'theme_card';
  static const themeCanvas = 'theme_canvas';
  static const themeTextPrimary = 'theme_text_primary';
  static const themeTextSecondary = 'theme_text_secondary';
  static const themeAccent = 'theme_accent';

  static const connectProvider = 'ConnectWidgetProvider';
  static const roomsProvider = 'RoomsWidgetProvider';
  static const membersProvider = 'MembersWidgetProvider';
}
