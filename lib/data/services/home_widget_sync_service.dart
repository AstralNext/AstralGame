import 'dart:convert';
import 'dart:io';

import 'package:astral_game/config/home_widget_keys.dart';
import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/data/services/home_widget_theme_sync.dart';
import 'package:astral_game/data/services/node_management_service.dart';
import 'package:astral_game/data/services/room_persistence_service.dart';
import 'package:astral_game/data/state/room_state.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/utils/room_display.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

/// 将连接状态、房间列表、在线成员写入 Android 桌面小部件缓存。
class HomeWidgetSyncService {
  Future<void> syncAll() async {
    if (!Platform.isAndroid) return;
    final settings = getIt<SettingsState>();
    await syncHomeWidgetTheme(settings.appThemeId.value);
    await Future.wait([
      syncConnect(),
      syncRooms(),
      syncMembers(),
    ]);
  }

  Future<void> syncConnect() async {
    if (!Platform.isAndroid) return;
    final roomState = getIt<RoomState>();
    final nodeManagement = getIt<NodeManagementService>();
    final inRoom = nodeManagement.isRunning;
    final selected = roomState.selectedRoom.value;
    final roomLabel = _resolveRoomLabel(roomState, selected, inRoom);
    final memberCount = nodeManagement.onlinePeersForDisplay.length;

    if (!inRoom) {
      await HomeWidget.saveWidgetData<String>(
        HomeWidgetKeys.connectRoomLabel,
        selected == null ? '未选择房间' : roomLabel,
      );
      await HomeWidget.saveWidgetData<String>(
        HomeWidgetKeys.connectRoomCode,
        selected?.shareCode.isNotEmpty == true
            ? selected!.shareCode
            : (selected?.roomName ?? ''),
      );
      await HomeWidget.saveWidgetData<String>(
        HomeWidgetKeys.connectStatus,
        '未连接',
      );
      await HomeWidget.saveWidgetData<String>(
        HomeWidgetKeys.connectStatusCode,
        'disconnected',
      );
      await HomeWidget.saveWidgetData<String>(
        HomeWidgetKeys.connectHint,
        selected == null
            ? '点击打开应用加入或创建房间'
            : '已选中 · 打开应用连接',
      );
    } else {
      final code = roomState.activeShareCode ??
          roomState.connectedRoomName.value ??
          selected?.shareCode ??
          '';
      await HomeWidget.saveWidgetData<String>(
        HomeWidgetKeys.connectRoomLabel,
        roomLabel,
      );
      await HomeWidget.saveWidgetData<String>(
        HomeWidgetKeys.connectRoomCode,
        code,
      );
      await HomeWidget.saveWidgetData<String>(
        HomeWidgetKeys.connectStatus,
        '已连接',
      );
      await HomeWidget.saveWidgetData<String>(
        HomeWidgetKeys.connectStatusCode,
        'connected',
      );
      await HomeWidget.saveWidgetData<String>(
        HomeWidgetKeys.connectHint,
        memberCount > 0 ? '在线 $memberCount 人 · 点击查看' : '已在房间中 · 点击查看',
      );
    }

    await HomeWidget.updateWidget(
      androidName: HomeWidgetKeys.connectProvider,
    );
  }

  Future<void> syncRooms() async {
    if (!Platform.isAndroid) return;
    var rooms = getIt<RoomState>().rooms;
    if (rooms.isEmpty && getIt.isRegistered<RoomPersistenceService>()) {
      rooms = await getIt<RoomPersistenceService>().loadRooms();
    }
    final preview = rooms.take(4).map(_roomToWidgetJson).toList();

    await HomeWidget.saveWidgetData<String>(
      HomeWidgetKeys.roomsJson,
      jsonEncode(preview),
    );
    await HomeWidget.saveWidgetData<String>(
      HomeWidgetKeys.roomsSummary,
      rooms.isEmpty
          ? '加入或创建房间后会出现在这里'
          : '共 ${rooms.length} 个 · 点击一行选中',
    );

    await HomeWidget.updateWidget(
      androidName: HomeWidgetKeys.roomsProvider,
    );
  }

  Future<void> syncMembers() async {
    if (!Platform.isAndroid) return;
    final roomState = getIt<RoomState>();
    final nodeManagement = getIt<NodeManagementService>();
    final inRoom = nodeManagement.isRunning;
    final selected = roomState.selectedRoom.value;
    final members = nodeManagement.onlinePeersForDisplay;
    final preview = members
        .take(6)
        .map((n) => n.displayName)
        .where((n) => n.isNotEmpty)
        .toList();

    await HomeWidget.saveWidgetData<String>(
      HomeWidgetKeys.membersRoomLabel,
      inRoom ? _resolveRoomLabel(roomState, selected, true) : '未在房间',
    );
    await HomeWidget.saveWidgetData<int>(
      HomeWidgetKeys.membersCount,
      members.length,
    );
    await HomeWidget.saveWidgetData<String>(
      HomeWidgetKeys.membersCountText,
      '${members.length}',
    );
    await HomeWidget.saveWidgetData<String>(
      HomeWidgetKeys.membersPreview,
      !inRoom
          ? '连接房间后显示在线成员'
          : (preview.isEmpty
              ? '暂无在线用户'
              : _formatMemberPreview(preview, members.length)),
    );

    await HomeWidget.updateWidget(
      androidName: HomeWidgetKeys.membersProvider,
    );
  }

  static String _resolveRoomLabel(
    RoomState roomState,
    RoomMod? selected,
    bool inRoom,
  ) {
    if (inRoom) {
      final active = activeRoomDisplayLabel(roomState);
      if (active != null && active.isNotEmpty) return active;
    }
    if (selected == null) {
      return inRoom ? '已连接' : '未在房间';
    }
    return roomDisplayLabel(selected);
  }

  static Map<String, dynamic> _roomToWidgetJson(RoomMod room) => {
        'label': roomDisplayLabel(room),
        'code': room.shareCode.isNotEmpty ? room.shareCode : room.roomName,
        'network': room.roomName,
        'id': room.id,
      };

  static String _formatMemberPreview(List<String> names, int total) {
    if (total <= names.length) return names.join(' · ');
    final extra = total - names.length;
    return '${names.join(' · ')} · +$extra';
  }
}

/// 后台/启动时刷新小部件（不阻塞 UI）。
Future<void> refreshAndroidHomeWidgets() {
  return HomeWidgetSyncService().syncAll();
}

/// 小组件后台回调：系统定时或点击刷新时重新拉取缓存。
@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!getIt.isRegistered<RoomPersistenceService>()) {
    await setupDI();
    final roomState = getIt<RoomState>();
    roomState.initPersistence(getIt<RoomPersistenceService>());
    await roomState.loadFromPersistence();
    roomState.restoreSelectedRoom(
      getIt<RoomPersistenceService>().loadSelectedRoomId(),
    );
    getIt<SettingsState>().loadFromPersistence();
  }
  await HomeWidgetSyncService().syncAll();
}
