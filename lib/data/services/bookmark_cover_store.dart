import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_core.dart';

/// 收藏房间的自定义封面。
///
/// 图片按收藏 id 存成支持目录下的 `cover-<id>.png`，**不写进 Isar**：
/// 加这个功能就不需要动数据库 schema（避免 Isar 迁移），封面文件也和收藏条目解耦。
/// 扩展名只是名义上的——Flutter 按字节内容识别格式，存 jpg/webp 也能正常解码。
///
/// 删除收藏时**故意不删**封面文件：删除操作带「撤销」，撤销后封面要还在；
/// 而收藏 id 由毫秒时间戳派生、永不复用，所以残留文件不会串到其它收藏上。
class BookmarkCoverStore {
  BookmarkCoverStore({required Directory? directory}) : _directory = directory;

  final Directory? _directory;

  /// 版本号：新增/移除封面后 +1。卡片 `Watch` 它即可立刻刷新。
  final revision = signal(0);

  File? fileFor(int id) {
    final dir = _directory;
    if (dir == null) return null;
    final file = File(p.join(dir.path, _fileName(id)));
    return file.existsSync() ? file : null;
  }

  bool hasCover(int id) => fileFor(id) != null;

  /// 保存封面（覆盖旧图）；失败返回 false，由 UI 提示。
  Future<bool> save(int id, Uint8List bytes) async {
    final dir = _directory;
    if (dir == null || bytes.isEmpty) return false;
    try {
      await dir.create(recursive: true);
      await File(
        p.join(dir.path, _fileName(id)),
      ).writeAsBytes(bytes, flush: true);
      revision.value = revision.value + 1;
      return true;
    } catch (e) {
      appLogger.w('[BookmarkCover] 保存封面失败 id=$id: $e');
      return false;
    }
  }

  /// 移除自定义封面（回到游戏默认封面）。
  Future<void> remove(int id) async {
    final dir = _directory;
    if (dir == null) return;
    try {
      final file = File(p.join(dir.path, _fileName(id)));
      if (file.existsSync()) await file.delete();
      revision.value = revision.value + 1;
    } catch (e) {
      appLogger.w('[BookmarkCover] 移除封面失败 id=$id: $e');
    }
  }

  static String _fileName(int id) => 'cover-$id.png';
}
