import 'package:astral_game/data/models/active_room_session.dart';
import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/data/services/room_persistence_service.dart';
import 'package:signals/signals_core.dart';

/// 房间会话状态；加入历史供桌面小部件与备份使用。
class RoomState {
  RoomPersistenceService? _persistence;

  final isConnected = signal<bool>(false);
  final session = signal<ActiveRoomSession?>(null);

  /// 房主「暂时退出」后的可恢复快照。
  final pausedHost = signal<HostResumeSnapshot?>(null);

  /// 强制结束提示（VPN 失败 / 房主离线等），UI 消费后应 [clearForceEndNotice]。
  final forceEndNotice = signal<String?>(null);

  /// 客人侧：房主当前是否在线（基于成员列表推断）。
  final hostOnline = signal<bool>(true);

  final roomsList = signal<List<RoomMod>>([]);
  final selectedRoom = signal<RoomMod?>(null);
  final connectedRoomName = signal<String?>(null);

  void initPersistence(RoomPersistenceService persistence) {
    _persistence = persistence;
  }

  Future<void> loadFromPersistence() async {
    final rooms = await _persistence?.loadRooms() ?? const <RoomMod>[];
    roomsList.value = rooms;
  }

  void restoreSelectedRoom(int? roomId) {
    if (roomId == null) {
      selectedRoom.value = null;
      return;
    }
    selectedRoom.value = _findById(roomId);
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
      unawaitedRecordHistory(value);
    }
  }

  /// 将当前会话写入加入历史（供小部件「我的房间」）。
  void unawaitedRecordHistory(ActiveRoomSession session) {
    // ignore: discarded_futures
    recordSessionHistory(session);
  }

  Future<void> recordSessionHistory(ActiveRoomSession session) async {
    final persistence = _persistence;
    if (persistence == null) return;

    final code = (session.shortCode ?? session.networkName).trim();
    if (code.isEmpty) return;

    final existing = roomsList.value;
    final now = DateTime.now();
    final incoming = RoomMod(
      id: now.millisecondsSinceEpoch,
      name: session.displayName.isNotEmpty
          ? session.displayName
          : (session.gameName.isNotEmpty ? session.gameName : code),
      roomName: session.networkName,
      host: '',
      port: 0,
      shareCode: session.shortCode ?? '',
      createdAt: now,
    );

    final next = RoomPersistenceService.upsertJoinHistory(existing, incoming);
    roomsList.value = next;
    await persistence.saveRooms(next);

    RoomMod? selected;
    final short = session.shortCode?.trim();
    for (final room in next) {
      if ((short != null && short.isNotEmpty && room.shareCode.trim() == short) ||
          room.roomName == session.networkName) {
        selected = room;
        break;
      }
    }
    setSelectedRoom(selected ?? (next.isNotEmpty ? next.first : null));
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

  void setSelectedRoom(RoomMod? room) {
    selectedRoom.value = room;
    final persistence = _persistence;
    if (persistence != null) {
      // ignore: discarded_futures
      persistence.saveSelectedRoomId(room?.id);
    }
  }

  void selectRoomById(int id) {
    final room = _findById(id);
    if (room != null) setSelectedRoom(room);
  }

  void selectRoomByCode(String code) {
    final key = code.trim();
    if (key.isEmpty) return;
    for (final room in roomsList.value) {
      if (room.shareCode.trim() == key || room.roomName == key) {
        setSelectedRoom(room);
        return;
      }
    }
  }

  void removeRoom(int roomId) {
    final next = roomsList.value.where((r) => r.id != roomId).toList();
    roomsList.value = next;
    if (selectedRoom.value?.id == roomId) {
      setSelectedRoom(null);
    }
    final persistence = _persistence;
    if (persistence != null) {
      // ignore: discarded_futures
      persistence.saveRooms(next);
    }
  }

  List<RoomMod> get rooms => roomsList.value;

  String? get activeShareCode => session.value?.shortCode;

  String? get activeRoomDisplayLabel {
    final s = session.value;
    if (s == null) return null;
    if (s.displayName.isNotEmpty) return s.displayName;
    return s.gameName.isNotEmpty ? s.gameName : s.networkName;
  }

  RoomMod? _findById(int id) {
    for (final room in roomsList.value) {
      if (room.id == id) return room;
    }
    return null;
  }
}
