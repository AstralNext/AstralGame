import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/data/services/room_persistence_service.dart';
import 'package:signals/signals_core.dart';

/// 房间会话状态（仅内存）。历史列表 API 保留空实现以兼容小组件/备份。
class RoomState {
  final isConnected = signal<bool>(false);
  final session = signal<ActiveRoomSession?>(null);

  /// 房主「暂时退出」后的可恢复快照。
  final pausedHost = signal<HostResumeSnapshot?>(null);

  /// 强制结束提示（被踢 / 房主离线等），UI 消费后应 [clearForceEndNotice]。
  final forceEndNotice = signal<String?>(null);

  /// 客人侧：房主当前是否在线（基于成员列表推断）。
  final hostOnline = signal<bool>(true);

  /// 兼容旧代码：始终空。
  final roomsList = signal<List<RoomMod>>([]);
  final selectedRoom = signal<RoomMod?>(null);
  final connectedRoomName = signal<String?>(null);

  void initPersistence(RoomPersistenceService persistence) {}

  Future<void> loadFromPersistence() async {
    roomsList.value = const [];
  }

  void restoreSelectedRoom(int? roomId) {
    selectedRoom.value = null;
  }

  void setConnected(bool value, {bool clearSession = true}) {
    isConnected.value = value;
    if (!value) {
      if (clearSession) {
        session.value = null;
      }
      connectedRoomName.value = null;
      hostOnline.value = true;
    }
  }

  void setSession(ActiveRoomSession? value) {
    session.value = value;
    connectedRoomName.value = value?.networkName;
    if (value != null) {
      hostOnline.value = true;
    }
  }

  void setPausedHost(HostResumeSnapshot? value) {
    pausedHost.value = value;
  }

  void setForceEndNotice(String? message) {
    forceEndNotice.value = message;
  }

  void clearForceEndNotice() {
    forceEndNotice.value = null;
  }

  void setHostOnline(bool value) {
    hostOnline.value = value;
  }

  void setConnectedRoomName(String? roomName) {
    connectedRoomName.value =
        roomName == null || roomName.trim().isEmpty ? null : roomName.trim();
  }

  void setSelectedRoom(RoomMod? room) {
    selectedRoom.value = room;
  }

  List<RoomMod> get rooms => roomsList.value;

  String? get activeShareCode => session.value?.shortCode;

  String? get activeRoomDisplayLabel {
    final s = session.value;
    if (s == null) return null;
    if (s.displayName.isNotEmpty) return s.displayName;
    return s.gameName.isNotEmpty ? s.gameName : s.networkName;
  }

  void removeRoom(int roomId) {}
}
