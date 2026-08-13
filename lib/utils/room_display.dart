import 'package:astral_game/data/models/room_mod.dart';

String roomDisplayLabel(RoomMod room) {
  final name = room.name.trim();
  if (name.isNotEmpty) return name;
  return room.roomName;
}
