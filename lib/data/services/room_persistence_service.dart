import 'dart:convert';
import 'dart:io';

import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';

/// 收藏读写：本地 `bookmarks.json`。
///
/// 不再有"加入历史（rooms.json）"与"自动写入"；一切皆为用户主动收藏。
class RoomPersistenceService {
  static const _fileName = 'bookmarks.json';

  Future<String> get _filePath async {
    final dir = await getApplicationSupportDirectory();
    return path_lib.join(dir.path, _fileName);
  }

  Future<List<Bookmark>> loadBookmarks() async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);
      final exists = file.existsSync();
      appLogger.d('[RoomPersistenceService] loadBookmarks: path=$filePath, exists=$exists');
      if (!exists) return const [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        appLogger.w('[RoomPersistenceService] bookmarks.json 为空文件');
        return const [];
      }
      final list = jsonDecode(content) as List;
      appLogger.d('[RoomPersistenceService] loadBookmarks: json 条目数=${list.length}');
      final result = <Bookmark>[];
      for (final e in list) {
        if (e is! Map<String, dynamic>) {
          appLogger.w('[RoomPersistenceService] 跳过非 Map 条目: ${e.runtimeType}');
          continue;
        }
        try {
          result.add(Bookmark.fromJson(e));
        } catch (err, stack) {
          appLogger.w(
            '[RoomPersistenceService] 跳过损坏条目: ${e['id'] ?? 'unknown'}, err=$err',
            error: err,
            stackTrace: stack,
          );
        }
      }
      appLogger.i('[RoomPersistenceService] loadBookmarks: 成功解析 ${result.length} / ${list.length} 条');
      return result;
    } catch (e, stackTrace) {
      appLogger.e('[RoomPersistenceService] 加载收藏整体失败: $e',
          error: e, stackTrace: stackTrace);
      return const [];
    }
  }

  Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    try {
      final filePath = await _filePath;
      final file = File(filePath);
      final json = jsonEncode(bookmarks.map((r) => r.toJson()).toList());
      await file.writeAsString(json);
      final size = await file.length();
      appLogger.i('[RoomPersistenceService] saveBookmarks: path=$filePath, count=${bookmarks.length}, bytes=$size');
    } catch (e, stackTrace) {
      appLogger.e('[RoomPersistenceService] 保存收藏失败: $e',
          error: e, stackTrace: stackTrace);
    }
  }

  /// 新收藏：末尾追加或覆盖同 id；置顶项排在前，其余按 sortKey 倒序。
  Future<List<Bookmark>> upsert(List<Bookmark> existing, Bookmark incoming) async {
    final rest = existing.where((b) => b.id != incoming.id).toList();
    final next = <Bookmark>[incoming, ...rest]..sort(_compare);
    await saveBookmarks(next);
    return next;
  }

  Future<List<Bookmark>> removeById(List<Bookmark> existing, int id) async {
    final next = existing.where((b) => b.id != id).toList()..sort(_compare);
    await saveBookmarks(next);
    return next;
  }

  /// 刷新 lastUsedAt（用户点"加入"时调用）。
  Future<List<Bookmark>> touchUsed(
    List<Bookmark> existing,
    int id, {
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final next = existing.map((b) {
      if (b.id != id) return b;
      return b.copyWith(lastUsedAt: now);
    }).toList()
      ..sort(_compare);
    await saveBookmarks(next);
    return next;
  }

  static int compare(Bookmark a, Bookmark b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.sortKey.compareTo(a.sortKey);
  }

  static int _compare(Bookmark a, Bookmark b) => compare(a, b);
}
