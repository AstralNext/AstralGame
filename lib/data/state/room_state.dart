import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/data/services/room_persistence_service.dart';
import 'package:astral_game/utils/room_display.dart' as room_display;
import 'package:signals/signals_core.dart';

/// 房间状态管理
///
/// 管理房间列表、选中的房间和连接状态
class RoomState {
  RoomPersistenceService? _persistence;

  /// 房间列表
  final roomsList = signal<List<RoomMod>>([]);

  /// 选中的房间 ID
  int? _selectedRoomId;

  /// 选中的房间
  final selectedRoom = signal<RoomMod?>(null);

  /// 连接状态
  final isConnected = signal<bool>(false);

  /// 当前 P2P 会话房间名（连接成功时写入，断开时清空）。
  final connectedRoomName = signal<String?>(null);

  /// 初始化持久化服务
  void initPersistence(RoomPersistenceService persistence) {
    _persistence = persistence;
  }

  /// 从持久化存储加载房间
  Future<void> loadFromPersistence() async {
    if (_persistence != null) {
      roomsList.value = await _persistence!.loadRooms();
    }
  }

  /// 恢复选中的房间（与 prefs 同步；无效 ID 时清空选中态）
  void restoreSelectedRoom(int? roomId) {
    _selectedRoomId = roomId;
    if (roomId == null) {
      selectedRoom.value = null;
      return;
    }
    final index = roomsList.value.indexWhere((r) => r.id == roomId);
    if (index != -1) {
      selectedRoom.value = roomsList.value[index];
    } else {
      selectedRoom.value = null;
    }
  }

  /// 设置连接状态
  void setConnected(bool value) {
    isConnected.value = value;
    if (!value) {
      connectedRoomName.value = null;
    }
  }

  void setConnectedRoomName(String? roomName) {
    connectedRoomName.value =
        roomName == null || roomName.trim().isEmpty ? null : roomName.trim();
  }

  /// 设置选中的房间
  void setSelectedRoom(RoomMod? room) {
    selectedRoom.value = room;
    if (room != null) {
      _selectedRoomId = room.id;
      _persistence?.saveSelectedRoomId(room.id);
    }
  }

  /// 获取房间列表
  List<RoomMod> get rooms => roomsList.value;

  /// 当前连接会话对应的房间记录（若有）。
  RoomMod? get activeSessionRoom => room_display.activeSessionRoom(this);

  /// 仪表盘 / 列表标题用房间名。
  String? get activeRoomDisplayLabel =>
      room_display.activeRoomDisplayLabel(this);

  /// 分享房间用分享码。
  String? get activeShareCode => room_display.activeRoomShareCode(this);

  /// 获取选中的房间 ID
  int? get selectedRoomId => _selectedRoomId;

  /// 移除房间
  void removeRoom(int roomId) {
    final updated = roomsList.value.where((r) => r.id != roomId).toList();
    roomsList.value = updated;
    _persistence?.saveRooms(updated);
    if (_selectedRoomId == roomId) {
      selectedRoom.value = null;
      _selectedRoomId = null;
      _persistence?.saveSelectedRoomId(null);
    }
  }
}
