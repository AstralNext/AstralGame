import 'dart:convert';
import 'dart:io';

import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/bookmark_record.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as path_lib;

/// 收藏持久化接口。
///
/// 只有四个操作，[RoomState] 依赖它而不是具体实现——测试可换成内存实现，
/// 不需要拉起真正的 Isar。
abstract class BookmarkStore {
  Future<List<Bookmark>> loadAll();

  /// 新增或覆盖（按 [Bookmark.id] 主键 upsert）。
  Future<void> save(Bookmark bookmark);

  Future<void> deleteById(int id);

  /// 刷新 lastUsedAt（用户点"加入"时调用）；记录不存在则忽略。
  Future<void> touchUsed(int id, DateTime at);
}

/// 基于 Isar 的实现。
///
/// 相比手写 JSON 的收益：写入走 Isar 事务（ACID），提交过的数据不会因
/// 进程被强杀而停在"写了一半"的中间态；并发/文件被占用由 Isar 内部处理，
/// 不再出现"整表序列化失败被静默吞掉"这种丢法。
class IsarBookmarkStore implements BookmarkStore {
  IsarBookmarkStore(this.isar);

  final Isar isar;

  IsarCollection<BookmarkRecord> get _collection =>
      isar.collection<BookmarkRecord>();

  /// 打开数据库（必要时创建目录），并做一次性旧数据导入。
  static Future<IsarBookmarkStore> open(String directory) async {
    await Directory(directory).create(recursive: true);
    final isar = await Isar.open(
      [BookmarkRecordSchema],
      directory: directory,
    );
    final store = IsarBookmarkStore(isar);
    await store._importLegacyJsonIfNeeded(directory);
    return store;
  }

  @override
  Future<List<Bookmark>> loadAll() async {
    final records = await _collection.where().findAll();
    final bookmarks = <Bookmark>[];
    for (final r in records) {
      bookmarks.add(toBookmark(r));
    }
    bookmarks.sort(compareBookmarks);
    return bookmarks;
  }

  @override
  Future<void> save(Bookmark bookmark) async {
    final record = toRecord(bookmark);
    await isar.writeTxn(() => _collection.put(record));
  }

  @override
  Future<void> deleteById(int id) async {
    await isar.writeTxn(() => _collection.delete(id));
  }

  @override
  Future<void> touchUsed(int id, DateTime at) async {
    await isar.writeTxn(() async {
      final record = await _collection.get(id);
      if (record == null) return;
      record.lastUsedAt = at;
      await _collection.put(record);
    });
  }

  /// 一次性导入旧版 `bookmarks.json`（仅在库为空时执行），随后把旧文件改名归档。
  ///
  /// 只在库为空时导入，避免覆盖已有数据；旧文件是"改名"而不是删除，
  /// 解析失败的条目仍留在归档文件里可人工抢救。
  Future<void> _importLegacyJsonIfNeeded(String directory) async {
    final file = File(path_lib.join(directory, legacyBookmarksFileName));
    if (!file.existsSync()) return;
    if (await _collection.count() > 0) return;

    final legacy = await readLegacyBookmarks(file);
    if (legacy.isNotEmpty) {
      await isar.writeTxn(
        () => _collection.putAll([for (final b in legacy) toRecord(b)]),
      );
      appLogger.i('[BookmarkStore] 已从 bookmarks.json 导入 ${legacy.length} 条收藏');
    }
    try {
      final archive =
          '${file.path}.migrated-${DateTime.now().millisecondsSinceEpoch}';
      await file.rename(archive);
      appLogger.i('[BookmarkStore] 旧 bookmarks.json 已归档: $archive');
    } catch (e) {
      appLogger.w('[BookmarkStore] 归档旧 bookmarks.json 失败: $e');
    }
  }
}

/// 旧版收藏文件名。
const legacyBookmarksFileName = 'bookmarks.json';

/// 读取旧版收藏文件；主文件不可用时回退到同目录的 `.bak`。
Future<List<Bookmark>> readLegacyBookmarks(File file) async {
  for (final candidate in [file, File('${file.path}.bak')]) {
    if (!candidate.existsSync()) continue;
    try {
      final parsed = parseLegacyBookmarksJson(await candidate.readAsString());
      if (parsed != null) return parsed;
    } catch (e) {
      appLogger.w('[BookmarkStore] 读取历史收藏失败 ${candidate.path}: $e');
    }
  }
  return const [];
}

/// 解析旧版 `bookmarks.json` 内容。
///
/// 返回 null 表示整体不可解析（JSON 非法或顶层不是数组）；空文件视为空列表。
/// 单条解析失败的条目跳过并记录，不影响其余条目导入。
List<Bookmark>? parseLegacyBookmarksJson(String content) {
  if (content.trim().isEmpty) return const [];
  final dynamic decoded;
  try {
    decoded = jsonDecode(content);
  } catch (e) {
    appLogger.w('[BookmarkStore] 历史收藏 JSON 解析失败: $e');
    return null;
  }
  if (decoded is! List) {
    appLogger.w('[BookmarkStore] 历史收藏顶层不是数组: ${decoded.runtimeType}');
    return null;
  }
  final bookmarks = <Bookmark>[];
  for (final e in decoded) {
    if (e is! Map<String, dynamic>) {
      appLogger.w('[BookmarkStore] 跳过非 Map 条目: ${e.runtimeType}');
      continue;
    }
    try {
      bookmarks.add(Bookmark.fromJson(e));
    } catch (err) {
      appLogger.w('[BookmarkStore] 历史收藏条目解析失败，跳过: ${e['id']}',
          error: err);
    }
  }
  return bookmarks;
}
