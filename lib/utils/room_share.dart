import 'package:astral_game/data/services/p2p_config_service.dart';
import 'package:astral_game/di.dart';

/// 复制到剪贴板用的分享码：`随机码_房间名`。
String roomShareCodeForClipboard(String storedShareCode) {
  final trimmed = storedShareCode.trim();
  if (trimmed.isEmpty) return trimmed;
  return getIt<P2PConfigService>().normalizeRoomShareCode(trimmed);
}
