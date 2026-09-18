import 'dart:convert';
import 'dart:io';

import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';

/// 收藏读写：本地 `bookmarks.json`。
///
/// 不再有"加入历史（rooms.json）"与"自动写入"；一切皆为用户主动收藏。
///
/// 持久化安全设计（防丢失三件套）：
/// 1. 原子写：先写 `bookmarks.json.tmp` 再 rename 覆盖正式文件，进程写入中途被杀
///    （断电 / 任务管理器 / 安装器强杀）也不会留下半截 JSON；
/// 2. 双保险：每次覆盖前把现有正式文件备份为 `bookmarks.json.bak`，正式文件
///    意外损坏时加载阶段自动回退到备份；
/// 3. 孤儿暂存：单条解析失败（典型：版本升级后 schema 不兼容）不丢弃，原样
///    留在内存并在下次保存时写回文件末尾，未来版本修复兼容后可自动找回。
class RoomPersistenceService {
  /// 可注入的存储目录（测试用）；为空时走 getApplicationSupportDirectory。
  RoomPersistenceService({String? directoryPath}) : _directoryPath = directoryPath;

  static const _fileName = 'bookmarks.json';

  final String? _directoryPath;

  /// 单条解析失败的原始条目；saveBookmarks 时原样写回，避免被后续保存清除。
  List<Map<String, dynamic>> _orphans = const [];

  Future<String> get _filePath async {
    if (_directoryPath != null) {
      return path_lib.join(_directoryPath, _fileName);
    }
    final dir = await getApplicationSupportDirectory();
    return path_lib.join(dir.path, _fileName);
  }

  Future<List<Bookmark>> loadBookmarks() async {
    _orphans = const [];
    try {
      final filePath = await _filePath;
      final file = File(filePath);
      final exists = file.existsSync();
      appLogger.d(
        '[RoomPersistenceService] loadBookmarks: path=$filePath, exists=$exists',
      );
      if (!exists) return const [];
      final content = await file.readAsString();
      final parsed = _parseContent(content);
      if (parsed != null) {
        _orphans = parsed.orphans;
        if (parsed.orphans.isNotEmpty) {
          appLogger.w(
            '[RoomPersistenceService] ${parsed.orphans.length} 条解析失败，已暂存等待写回（不会被清除）',
          );
        }
        appLogger.i(
          '[RoomPersistenceService] loadBookmarks: 成功解析 ${parsed.bookmarks.length} 条'
          '${parsed.orphans.isEmpty ? '' : '（另有孤儿 ${parsed.orphans.length} 条）'}',
        );
        return parsed.bookmarks;
      }

      // 正式文件整体损坏：尝试从 .bak 恢复。
      appLogger.e('[RoomPersistenceService] bookmarks.json 整体损坏，尝试从 .bak 恢复');
      final recovered = await _recoverFromBackup(filePath);
      if (recovered != null) return recovered;

      // .bak 也不可用：隔离损坏文件留证（不直接清空覆盖），供用户手动抢救。
      await _quarantineCorruptFile(file);
      return const [];
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
      final json = jsonEncode([
        ...bookmarks.map((r) => r.toJson()),
        ..._orphans,
      ]);
      // 原子写：tmp → 备份旧文件 → rename 覆盖。
      final tmp = File('$filePath.tmp');
      await tmp.writeAsString(json, flush: true);
      if (file.existsSync()) {
        try {
          await file.copy('$filePath.bak');
        } catch (e) {
          // 备份失败不阻塞主流程（.bak 只是二级保险）。
          appLogger.w('[RoomPersistenceService] 备份 .bak 失败（继续写入）: $e');
        }
      }
      await tmp.rename(filePath);
      final size = await file.length();
      appLogger.i(
        '[RoomPersistenceService] saveBookmarks: path=$filePath, count=${bookmarks.length}, bytes=$size',
      );
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

  // ---------------- 解析与恢复 ----------------

  /// 解析文件内容；返回 null 表示整体损坏（JSON 非法或顶层不是数组）。
  /// 空文件视为合法的空列表（用户清空收藏是正常操作，不能用 .bak 覆盖）。
  _ParsedBookmarks? _parseContent(String content) {
    if (content.trim().isEmpty) {
      return const _ParsedBookmarks([], []);
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (e) {
      appLogger.w('[RoomPersistenceService] JSON 解析失败: $e');
      return null;
    }
    if (decoded is! List) {
      appLogger.w('[RoomPersistenceService] 顶层不是数组: ${decoded.runtimeType}');
      return null;
    }
    final bookmarks = <Bookmark>[];
    final orphans = <Map<String, dynamic>>[];
    for (final e in decoded) {
      if (e is! Map<String, dynamic>) {
        appLogger.w('[RoomPersistenceService] 跳过非 Map 条目: ${e.runtimeType}');
        continue;
      }
      try {
        bookmarks.add(Bookmark.fromJson(e));
      } catch (err, stack) {
        // 解析失败不丢弃：进孤儿列表，保存时原样写回。
        appLogger.w(
          '[RoomPersistenceService] 条目解析失败，暂存为孤儿: ${e['id'] ?? 'unknown'}, err=$err',
          error: err,
          stackTrace: stack,
        );
        orphans.add(e);
      }
    }
    return _ParsedBookmarks(bookmarks, orphans);
  }

  /// 正式文件损坏时，从 `bookmarks.json.bak` 恢复并回写正式文件。
  /// 返回 null 表示备份不存在或同样损坏。
  Future<List<Bookmark>?> _recoverFromBackup(String filePath) async {
    final bak = File('$filePath.bak');
    if (!bak.existsSync()) {
      appLogger.w('[RoomPersistenceService] 无 .bak 备份可恢复');
      return null;
    }
    try {
      final content = await bak.readAsString();
      final parsed = _parseContent(content);
      if (parsed == null) {
        appLogger.w('[RoomPersistenceService] .bak 同样损坏，放弃恢复');
        return null;
      }
      // 用备份内容原子恢复正式文件（先损坏的正式文件此刻还在，等会儿统一隔离）。
      final tmp = File('$filePath.tmp');
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(filePath);
      _orphans = parsed.orphans;
      appLogger.w(
        '[RoomPersistenceService] 已从 .bak 恢复 ${parsed.bookmarks.length} 条收藏',
      );
      return parsed.bookmarks;
    } catch (e) {
      appLogger.w('[RoomPersistenceService] 读取 .bak 失败: $e');
      return null;
    }
  }

  /// 把损坏文件改名为 `bookmarks.json.corrupt-<时间戳>` 留证，
  /// 避免下一次保存直接覆盖导致数据彻底无法抢救。
  Future<void> _quarantineCorruptFile(File file) async {
    try {
      if (!file.existsSync()) return;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final quarantined = '${file.path}.corrupt-$ts';
      await file.rename(quarantined);
      appLogger.w(
        '[RoomPersistenceService] 损坏文件已隔离: $quarantined（可手动从中抢救数据）',
      );
    } catch (e) {
      appLogger.w('[RoomPersistenceService] 隔离损坏文件失败: $e');
    }
  }
}

/// 解析结果：有效收藏 + 无法解析的孤儿原始条目。
class _ParsedBookmarks {
  const _ParsedBookmarks(this.bookmarks, this.orphans);

  final List<Bookmark> bookmarks;
  final List<Map<String, dynamic>> orphans;
}
