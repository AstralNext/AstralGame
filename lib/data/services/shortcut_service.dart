import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';
import 'package:win32_registry/win32_registry.dart';

/// Windows / Android 平台的桌面快捷方式服务。
///
/// - Windows：用 win32 FFI 的 IShellLinkW + IPersistFile 创建真正的 .lnk。
///   图标支持 PNG-in-ICO（Windows Vista+ 原生支持），纯 Dart 写 ICO 头。
/// - Android：用 ShortcutManager.requestPinShortcut()。
class ShortcutService {

  const ShortcutService();
  static const _channel = MethodChannel('astral.game/shortcut');

  Future<bool> createDesktopShortcut({required Bookmark bookmark}) async {
    if (Platform.isAndroid) return _createAndroidShortcut(bookmark);
    if (Platform.isWindows) return _createWindowsShortcut(bookmark);
    throw ShortcutException('不支持的平台：${Platform.operatingSystem}');
  }

  // ======================================================================
  // Android
  // ======================================================================

  Future<bool> _createAndroidShortcut(Bookmark bookmark) async {
    final game = GameCatalog.byId(bookmark.payload.gameId);
    final args = <String, dynamic>{
      'id': 'room_${bookmark.id}',
      'label': bookmark.displayName,
      'url': 'astralgame://join?bookmark=${bookmark.id}',
      'gameColor': game?.color.toARGB32(),
    };

    // Flutter 端先解析真正的图标 bytes（完整的 asset→network hybrid 兜底），
    // 直接传给 Android，避免 Kotlin 端自己处理 asset/network 路径问题。
    final iconBytes = await _resolveAndroidIconBytes(game);
    if (iconBytes != null) {
      args['iconBytes'] = iconBytes;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'createPinnedShortcut',
        args,
      );
      return result == true;
    } on PlatformException catch (e) {
      if (e.code == 'NO_PERMISSION') {
        throw ShortcutException(
          '系统权限不足：请在系统设置中允许 Astral Game 创建快捷方式',
          code: ShortcutErrorCode.noPermission,
        );
      }
      if (e.code == 'UNSUPPORTED') {
        throw ShortcutException(
          '当前系统不支持桌面快捷方式（需要 Android 8.0+）',
          code: ShortcutErrorCode.unsupported,
        );
      }
      rethrow;
    }
  }

  /// 拿到 Android 快捷方式需要的 PNG bytes。
  /// 优先尝试 Flutter 打包的 asset → 失败再走远程 CDN。
  Future<Uint8List?> _resolveAndroidIconBytes(GameInfo? game) async {
    if (game == null) return null;
    final ref = GameMediaRef.tryParse(game.resolvedIconAsset);
    if (ref == null) return null;

    // 1) asset 或 hybrid 本地路径
    if (ref.kind == GameMediaKind.asset ||
        ref.kind == GameMediaKind.hybrid) {
      final assetPath = ref.path;
      if (assetPath != null) {
        try {
          final bytes = await rootBundle.load(assetPath);
          final list = bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          );
          if (list.isNotEmpty) return list;
        } catch (_) {}
      }
    }

    // 2) network 或 hybrid 远程兜底
    final url = ref.kind == GameMediaKind.network
        ? ref.url
        : ref.kind == GameMediaKind.hybrid
            ? ref.url
            : null;
    if (url != null) {
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode == 200) {
          final sink = BytesBuilder();
          await for (final chunk in response) {
            sink.add(chunk);
          }
          final result = sink.toBytes();
          if (result.isNotEmpty) return result;
        }
      } catch (_) {}
    }
    return null;
  }

  // ======================================================================
  // Windows —— 纯 Dart + win32 FFI
  // ======================================================================

  Future<bool> _createWindowsShortcut(Bookmark bookmark) async {
    final desktopDir = _findWindowsDesktopDir();
    if (desktopDir == null || desktopDir.isEmpty) {
      throw ShortcutException(
        '无法定位桌面路径（是否被 OneDrive 重定向？）',
        code: ShortcutErrorCode.desktopNotFound,
      );
    }

    final exe = Platform.resolvedExecutable;
    final url = 'astralgame://join?bookmark=${bookmark.id}';
    final safeName = bookmark.displayName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    if (safeName.isEmpty) throw ShortcutException('快捷方式名字为空');

    // 解析图标：游戏图标 → 转 ICO；没图标就用 exe 自带
    String? iconPath;
    final game = GameCatalog.byId(bookmark.payload.gameId);
    if (game != null) {
      final pngPath = await _resolveGameIconFile(game);
      if (pngPath != null) {
        final tempDir = await getTemporaryDirectory();
        iconPath = '${tempDir.path}\\astral_${game.id}.ico';
        await _writeIcoFromPng(File(pngPath), File(iconPath));
      }
    }
    final finalIcon = iconPath ?? exe;

    final lnkPath = '$desktopDir\\$safeName.lnk';
    final result = _writeWindowsLnk(
      lnkPath: lnkPath,
      target: exe,
      arguments: url,
      iconPath: finalIcon,
      description: '加入 Astral Game 房间：${bookmark.displayName}',
    );
    if (!result) {
      throw ShortcutException('创建 .lnk 失败');
    }
    appLogger.i('[Shortcut] 创建桌面快捷方式: $lnkPath');
    return true;
  }

  /// 用 win32 COM 创建真正的 Windows 快捷方式（.lnk）。
  bool _writeWindowsLnk({
    required String lnkPath,
    required String target,
    required String arguments,
    required String iconPath,
    required String description,
  }) {
    final lnkPathPtr = lnkPath.toNativeUtf16();
    final targetPtr = target.toNativeUtf16();
    final argsPtr = arguments.toNativeUtf16();
    final iconPtr = iconPath.toNativeUtf16();
    final descPtr = description.toNativeUtf16();

    try {
      final shellLink = ShellLink.createInstance();
      shellLink.setPath(targetPtr);
      shellLink.setArguments(argsPtr);
      shellLink.setIconLocation(iconPtr, 0);
      shellLink.setDescription(descPtr);

      final persistFile = IPersistFile.from(shellLink);
      final hr = persistFile.save(lnkPathPtr, TRUE);
      persistFile.release();
      shellLink.release();

      if (hr < 0) {
        appLogger.e('[Shortcut] IPersistFile.save 失败: HRESULT=0x${hr.toRadixString(16)}');
        return false;
      }
      return File(lnkPath).existsSync();
    } catch (e) {
      appLogger.e('[Shortcut] 创建 .lnk 异常: $e');
      return false;
    } finally {
      calloc.free(lnkPathPtr);
      calloc.free(targetPtr);
      calloc.free(argsPtr);
      calloc.free(iconPtr);
      calloc.free(descPtr);
    }
  }

  // ======================================================================
  // 桌面路径
  // ======================================================================

  String? _findWindowsDesktopDir() {
    try {
      const key =
          r'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders';
      final hive = Registry.openPath(RegistryHive.currentUser, path: key);
      final val = hive.getValue('Desktop');
      hive.close();
      final String? raw = switch (val) {
        StringValue(:final value) => value,
        UnexpandedStringValue(:final value) => value,
        LinkValue(:final value) => value,
        _ => null,
      };
      if (raw != null && raw.isNotEmpty) {
        final expanded = raw.replaceAllMapped(
          RegExp(r'%([^%]+)%'),
          (m) => Platform.environment[m.group(1)!] ?? m.group(0)!,
        );
        if (Directory(expanded).existsSync()) return expanded;
      }
    } catch (e) {
      appLogger.w('[Shortcut] 读取桌面路径失败: $e');
    }
    final home = Platform.environment['USERPROFILE'];
    if (home != null) {
      final d = '$home\\Desktop';
      if (Directory(d).existsSync()) return d;
    }
    return null;
  }

  // ======================================================================
  // 图标下载 + PNG → ICO（纯 Dart）
  // ======================================================================

  Future<String?> _resolveGameIconFile(GameInfo game) async {
    final ref = GameMediaRef.tryParse(game.resolvedIconAsset);
    if (ref == null) return null;
    final tempDir = await getTemporaryDirectory();
    final iconTarget = File('${tempDir.path}\\astral_raw_${game.id}.png');

    if (ref.kind == GameMediaKind.asset) {
      try {
        final bytes = await rootBundle.load(ref.path!);
        await iconTarget.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        return iconTarget.path;
      } catch (e) {
        appLogger.w('[Shortcut] 加载 asset 图标失败: $e');
      }
      return null;
    }

    final url = ref.kind == GameMediaKind.network ? ref.url! : ref.url;
    if (url == null) return null;
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        final sink = iconTarget.openWrite();
        await response.pipe(sink);
        await sink.flush();
        await sink.close();
        return iconTarget.path;
      }
    } catch (e) {
      appLogger.w('[Shortcut] 下载游戏图标失败: $e');
    }
    return null;
  }

  /// 把 PNG 文件包装成 ICO（Windows Vista+ 原生支持 PNG-in-ICO）。
  ///
  /// ICO 格式：
  ///   6 字节头: reserved(0) + type(1) + count
  ///   每条 16 字节目录项: w + h + colors + reserved + planes + bpp + size + offset
  ///   然后是 PNG 原始字节
  Future<void> _writeIcoFromPng(File png, File ico) async {
    final pngBytes = await png.readAsBytes();
    if (pngBytes.length < 24) return;

    // 从 PNG IHDR chunk 读宽高（都是 4 字节 big-endian）：
    //   0-7:  PNG签名
    //   8-11: IHDR chunk length
    //   12-15: IHDR ASCII tag
    //   16-19: width (4 bytes, BE)
    //   20-23: height (4 bytes, BE)
    final bd = pngBytes.buffer.asByteData(
      16,
      8, // width 4 bytes + height 4 bytes = 8 bytes
    );
    final w = bd.getUint32(0, Endian.big);
    final h = bd.getUint32(4, Endian.big);

    // ICO header: 6 字节
    final header = ByteData(6);
    header.setUint16(0, 0, Endian.little); // reserved
    header.setUint16(2, 1, Endian.little); // type = 1 (icon)
    header.setUint16(4, 1, Endian.little); // count = 1

    // ICO directory entry: 16 字节
    final dir = ByteData(16);
    dir.setUint8(0, w > 255 ? 0 : w);
    dir.setUint8(1, h > 255 ? 0 : h);
    dir.setUint8(2, 0); // color count
    dir.setUint8(3, 0); // reserved
    dir.setUint16(4, 1, Endian.little); // color planes
    dir.setUint16(6, 32, Endian.little); // bits per pixel
    dir.setUint32(8, pngBytes.length, Endian.little); // size of image data
    dir.setUint32(12, 22, Endian.little); // offset = 6 + 16 = 22

    final output = <int>[
      ...header.buffer.asUint8List(),
      ...dir.buffer.asUint8List(),
      ...pngBytes,
    ];
    await ico.writeAsBytes(output);
  }
}

class ShortcutException implements Exception {
  ShortcutException(this.message, {this.code});
  final String message;
  final ShortcutErrorCode? code;
  @override
  String toString() => message;
}

enum ShortcutErrorCode {
  noPermission,
  unsupported,
  desktopNotFound,
}
