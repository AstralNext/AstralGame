import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/data/state/room_state.dart';

/// UI 用房间展示名：优先用户设置的 [RoomMod.name]，否则 [RoomMod.roomName]。
String roomDisplayLabel(RoomMod room) {
  final label = room.name.trim();
  if (label.isNotEmpty) return label;
  final network = room.roomName.trim();
  if (network.isNotEmpty) return network;
  return '未命名房间';
}

/// 当前会话在界面上的房间名（已连接时）。
String? activeRoomDisplayLabel(RoomState state) {
  final room = activeSessionRoom(state);
  if (room != null) return roomDisplayLabel(room);
  final network = state.connectedRoomName.value?.trim();
  if (network != null && network.isNotEmpty) return network;
  return null;
}

/// 当前会话关联的历史房间记录（若有）。
RoomMod? activeSessionRoom(RoomState state) {
  final selected = state.selectedRoom.value;
  if (selected != null) return selected;
  if (!state.isConnected.value) return null;
  final network = state.connectedRoomName.value?.trim();
  if (network == null || network.isEmpty) return null;
  for (final room in state.rooms) {
    if (room.roomName == network) return room;
  }
  return null;
}

String? activeRoomShareCode(RoomState state) =>
    activeSessionRoom(state)?.shareCode.trim();

/// 加入历史列表副标题：有自定义展示名时显示网络名，否则显示分享码摘要。
String historyItemSubtitle(RoomMod room) {
  final display = room.name.trim();
  final network = room.roomName.trim();
  final share = room.shareCode.trim();
  if (display.isNotEmpty && network.isNotEmpty && display != network) {
    return '网络名：$network';
  }
  if (share.isEmpty) {
    return network.isNotEmpty ? network : '本地房间';
  }
  if (share.length <= AppConstants.uuidDisplayLength) return share;
  return '${share.substring(0, AppConstants.uuidDisplayLength)}...';
}
