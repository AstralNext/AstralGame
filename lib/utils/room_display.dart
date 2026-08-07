import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/data/state/room_state.dart';

String? activeRoomDisplayLabel(RoomState state) =>
    state.activeRoomDisplayLabel;

String? activeRoomShareCode(RoomState state) => state.activeShareCode;

String roomDisplayLabel(RoomMod room) {
  final name = room.name.trim();
  if (name.isNotEmpty) return name;
  return room.roomName;
}
