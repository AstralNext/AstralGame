import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/utils/room_share.dart';

String? activeRoomDisplayLabel(RoomState state) =>
    state.activeRoomDisplayLabel;

String? activeRoomShareCode(RoomState state) => state.activeShareCode;

String roomDisplayLabel(RoomMod room) {
  final name = room.name.trim();
  if (name.isNotEmpty) return name;
  return room.roomName;
}

String historyItemSubtitle(RoomMod room) {
  final code = room.shareCode.trim();
  if (looksLikeShortCode(code)) return code;
  if (looksLikeOfflineInvite(code)) return '离线邀请';
  if (code.isNotEmpty) return code;
  return room.roomName;
}
