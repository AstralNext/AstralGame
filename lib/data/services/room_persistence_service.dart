import 'dart:convert';
import 'dart:io';

import 'package:astral_game/config/constants.dart';
import 'package:astral_game/data/models/room_mod.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RoomPersistenceService {
  static const _fileName = 'rooms.json';
  static const _selectedRoomKey = 'selected_room_id';

  final SharedPreferences _prefs;

  RoomPersistenceService(this._prefs);

  Future<String> get _filePath async {
    final dir = await getApplicationSupportDirectory();
    return path_lib.join(dir.path, _fileName);
  }

  Future<List<RoomMod>> loadRooms() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List;
      final rooms = list
          .map((e) => RoomMod.fromJson(e as Map<String, dynamic>))
          .toList();
      return normalizeJoinHistory(rooms);
    } catch (e) {
      return [];
    }
  }

  /// 最新在前；相同 [RoomMod.shareCode] 只保留一条（保留较新的访问时间）。
  static List<RoomMod> normalizeJoinHistory(List<RoomMod> rooms) {
    final byShareCode = <String, RoomMod>{};
    final withoutShareCode = <RoomMod>[];

    for (final room in rooms) {
      final key = room.shareCode.trim();
      if (key.isEmpty) {
        withoutShareCode.add(room);
        continue;
      }
      final existing = byShareCode[key];
      if (existing == null || room.createdAt.isAfter(existing.createdAt)) {
        byShareCode[key] = room;
      }
    }

    final merged = [...byShareCode.values, ...withoutShareCode]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return merged.take(AppConstants.maxJoinHistoryEntries).toList();
  }

  /// 写入一条加入/创建记录：同分享码移到最前并刷新时间，总数不超过上限。
  static List<RoomMod> upsertJoinHistory(List<RoomMod> existing, RoomMod incoming) {
    final key = incoming.shareCode.trim();
    final rest = key.isEmpty
        ? List<RoomMod>.from(existing)
        : existing.where((r) => r.shareCode.trim() != key).toList();

    var entry = incoming;
    if (key.isNotEmpty) {
      for (final old in existing) {
        if (old.shareCode.trim() != key) continue;
        entry = RoomMod(
          id: old.id,
          name: incoming.name,
          roomName: incoming.roomName,
          host: incoming.host,
          port: incoming.port,
          password: incoming.password,
          shareCode: incoming.shareCode,
          createdAt: DateTime.now(),
        );
        break;
      }
    }

    return [entry, ...rest].take(AppConstants.maxJoinHistoryEntries).toList();
  }

  Future<void> saveRooms(List<RoomMod> rooms) async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);
      final json = jsonEncode(rooms.map((r) => r.toJson()).toList());
      await file.writeAsString(json);
    } catch (e, stackTrace) {
      appLogger.e('[RoomPersistenceService] 保存房间失败: $e', error: e, stackTrace: stackTrace);
    }
  }

  int? loadSelectedRoomId() {
    return _prefs.getInt(_selectedRoomKey);
  }

  Future<void> saveSelectedRoomId(int? id) async {
    if (id == null) {
      await _prefs.remove(_selectedRoomKey);
    } else {
      await _prefs.setInt(_selectedRoomKey, id);
    }
  }
}
