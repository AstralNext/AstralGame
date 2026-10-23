import 'package:file/file.dart' as pkgfile;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 游戏图标/封面的磁盘缓存。
///
/// 图片不再打包进应用（否则安装包多出 20 MB+），改为首次使用时从 CDN 下载，
/// 落到应用支持目录后长期复用。默认的 flutter_cache_manager 把文件放在
/// `%TEMP%`，系统清理后会重新下载，所以这里换成稳定的支持目录。
class GameMediaCache {
  GameMediaCache._();

  /// 缓存保留一年，游戏图片基本不会变；容量上限按对象数兜底。
  static final CacheManager manager = CacheManager(
    Config(
      'astral_game_media',
      stalePeriod: const Duration(days: 3650),
      maxNrOfCacheObjects: 200,
      fileSystem: _SupportDirFileSystem(),
    ),
  );
}

/// 把缓存目录指向 `supportDir/game_media`。
class _SupportDirFileSystem implements FileSystem {
  Future<pkgfile.Directory>? _dirFuture;

  Future<pkgfile.Directory> _dir() => _dirFuture ??= _create();

  Future<pkgfile.Directory> _create() async {
    final support = await getApplicationSupportDirectory();
    const local = LocalFileSystem();
    final dir = local.directory(p.join(support.path, 'game_media'));
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<pkgfile.File> createFile(String name) async {
    final dir = await _dir();
    return dir.childFile(name);
  }
}
