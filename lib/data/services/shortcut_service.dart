import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:astral_game/data/models/bookmark.dart';
import 'package:astral_game/data/models/game_catalog.dart';
import 'package:astral_game/data/services/game_media_cache.dart';
import 'package:astral_game/utils/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';
import 'package:win32_registry/win32_registry.dart';

/// Windows / Android 平台的桌面快捷方式服务。
///
/// - Windows：用 win32 FFI 的 IShellLinkW + IPersistFile 创建真正的 .lnk。
///   图标统一解码成 256×256 PNG 再包一层 ICO 头，兼容 PNG/JPEG 源图。
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

    // Flutter 端先解析真正的图标 bytes（asset → network 兜底），
    // 直接传给 Android，避免 Kotlin 端自己处理 asset/network 路径问题。
    final iconBytes = await _resolveGameIconBytes(game);
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
      if (e.code == 'FAILED') {
        throw ShortcutException('创建快捷方式失败：${e.message ?? '系统未响应'}');
      }
      rethrow;
    }
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
    final exeDir = File(exe).parent.path;
    final url = 'astralgame://join?bookmark=${bookmark.id}';
    final safeName = _safeShortcutName(bookmark.displayName);

    // 解析图标：游戏图标 → 统一转成 256×256 的 ICO；没有图标就用 exe 自带。
    String? iconPath;
    final game = GameCatalog.byId(bookmark.payload.gameId);
    if (game != null) {
      final rawIcon = await _resolveGameIconBytes(game);
      if (rawIcon != null) {
        final icoBytes = _buildIcoBytes(rawIcon);
        if (icoBytes != null && icoBytes.isNotEmpty) {
          iconPath = await _writeShortcutIcon(gameId: game.id, bytes: icoBytes);
          appLogger.i(
            '[Shortcut] 图标已生成 ${game.id}: '
            'raw=${rawIcon.length}B ico=${icoBytes.length}B $iconPath',
          );
        } else {
          appLogger.w('[Shortcut] 图标解码失败，回退 exe 图标: ${game.id}');
        }
      } else {
        appLogger.w('[Shortcut] 未取到游戏图标，回退 exe 图标: ${game.id}');
      }
    }
    final finalIcon = iconPath ?? exe;

    final lnkPath = '$desktopDir\\$safeName.lnk';
    _writeWindowsLnk(
      lnkPath: lnkPath,
      target: exe,
      arguments: url,
      workingDirectory: exeDir,
      iconPath: finalIcon,
      description: '加入 Astral Game 房间：${bookmark.displayName}',
    );
    appLogger.i('[Shortcut] 创建桌面快捷方式: $lnkPath');
    return true;
  }

  /// 快捷方式文件名：去掉 Windows 非法字符、结尾的点/空格，避开保留设备名。
  String _safeShortcutName(String raw) {
    var name = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    // Windows 不允许文件名以点或空格结尾（资源管理器会静默截断）。
    name = name.replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty) name = 'Astral 房间';
    const reserved = {
      'CON', 'PRN', 'AUX', 'NUL', //
      'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
      'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
    };
    if (reserved.contains(name.toUpperCase())) name = '_$name';
    // 控制总长度，避免桌面路径过长导致 IPersistFile 保存失败。
    if (name.runes.length > 80) {
      name = String.fromCharCodes(name.runes.take(80));
    }
    return name;
  }

  /// 用 win32 COM 创建真正的 Windows 快捷方式（.lnk）。
  void _writeWindowsLnk({
    required String lnkPath,
    required String target,
    required String arguments,
    required String workingDirectory,
    required String iconPath,
    required String description,
  }) {
    // Dart 跑在独立的 UI 线程，进程启动时 runner 的 CoInitializeEx 不覆盖这里，
    // 不初始化会直接 CoCreateInstance 失败（CO_E_NOTINITIALIZED / 0x800401F0）。
    final coHr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    final shouldUninitialize = coHr >= 0;
    if (coHr < 0) {
      appLogger.w(
        '[Shortcut] CoInitializeEx 失败: HRESULT=0x${coHr.toRadixString(16)}',
      );
    }

    final lnkPathPtr = lnkPath.toNativeUtf16();
    final targetPtr = target.toNativeUtf16();
    final argsPtr = arguments.toNativeUtf16();
    final workDirPtr = workingDirectory.toNativeUtf16();
    final iconPtr = iconPath.toNativeUtf16();
    final descPtr = description.toNativeUtf16();

    try {
      final shellLink = ShellLink.createInstance();
      shellLink.setPath(targetPtr);
      shellLink.setArguments(argsPtr);
      shellLink.setWorkingDirectory(workDirPtr);
      shellLink.setIconLocation(iconPtr, 0);
      shellLink.setDescription(descPtr);

      final persistFile = IPersistFile.from(shellLink);
      final hr = persistFile.save(lnkPathPtr, TRUE);
      persistFile.release();
      shellLink.release();

      if (hr < 0) {
        throw ShortcutException('创建快捷方式失败: HRESULT=0x${hr.toRadixString(16)}');
      }
      if (!File(lnkPath).existsSync()) {
        throw ShortcutException('快捷方式创建后文件不存在');
      }
    } catch (e) {
      if (e is ShortcutException) rethrow;
      throw ShortcutException('创建快捷方式失败: $e');
    } finally {
      calloc.free(lnkPathPtr);
      calloc.free(targetPtr);
      calloc.free(argsPtr);
      calloc.free(workDirPtr);
      calloc.free(iconPtr);
      calloc.free(descPtr);
      if (shouldUninitialize) CoUninitialize();
    }
  }

  // ======================================================================
  // 桌面路径
  // ======================================================================

  String? _findWindowsDesktopDir() {
    // 首选 Known Folder API：能正确处理 OneDrive 重定向、企业重定向和组策略。
    final known = _desktopFromKnownFolder();
    if (known != null) return known;

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
      appLogger.w('[Shortcut] 读取桌面路径(注册表)失败: $e');
    }

    final home = Platform.environment['USERPROFILE'];
    if (home != null) {
      final d = '$home\\Desktop';
      if (Directory(d).existsSync()) return d;
    }

    // OneDrive 重定向桌面兜底（注册表读不到时）
    for (final env in const [
      'OneDrive',
      'OneDriveCommercial',
      'OneDriveConsumer',
    ]) {
      final base = Platform.environment[env];
      if (base != null && base.isNotEmpty) {
        final d = '$base\\Desktop';
        if (Directory(d).existsSync()) return d;
      }
    }
    return null;
  }

  /// SHGetKnownFolderPath(FOLDERID_Desktop)：桌面被重定向时也能拿到真实路径。
  String? _desktopFromKnownFolder() {
    Pointer<GUID>? guid;
    Pointer<Pointer<Utf16>>? outPath;
    try {
      guid = GUIDFromString(FOLDERID_Desktop);
      outPath = calloc<Pointer<Utf16>>();
      final hr = SHGetKnownFolderPath(guid, 0, 0, outPath);
      if (hr < 0) return null;
      final ptr = outPath.value;
      if (ptr == nullptr) return null;
      final path = ptr.toDartString();
      return path.isEmpty ? null : path;
    } catch (e) {
      appLogger.w('[Shortcut] SHGetKnownFolderPath 失败: $e');
      return null;
    } finally {
      if (outPath != null) {
        final ptr = outPath.value;
        if (ptr != nullptr) CoTaskMemFree(ptr.cast());
        calloc.free(outPath);
      }
      if (guid != null) calloc.free(guid);
    }
  }

  // ======================================================================
  // 图标下载 + 图片 → ICO
  // ======================================================================

  /// 取游戏图标的原始字节：本地 asset 优先（hybrid 也一样），失败再走远程。
  Future<Uint8List?> _resolveGameIconBytes(GameInfo? game) async {
    if (game == null) return null;
    final ref = GameMediaRef.tryParse(game.resolvedIconAsset);
    if (ref == null) return null;

    final assetPath = ref.path;
    if (assetPath != null && assetPath.isNotEmpty) {
      try {
        final bytes = await rootBundle.load(assetPath);
        final list = bytes.buffer.asUint8List(
          bytes.offsetInBytes,
          bytes.lengthInBytes,
        );
        if (list.isNotEmpty) return list;
      } catch (e) {
        appLogger.t('[Shortcut] 加载 asset 图标失败: $e');
      }
    }

    final url = ref.url;
    if (url == null || url.isEmpty) return null;
    try {
      // 走统一的游戏图片缓存：已下载过就直接读本地文件，不再重复请求。
      final file = await GameMediaCache.manager.getSingleFile(url);
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (e) {
      appLogger.w('[Shortcut] 下载游戏图标失败: $e');
      return null;
    }
  }

  /// 图标写到支持目录（不能放 %TEMP%：清理后会变成空白图标）。
  /// 文件名带内容哈希，图标更新后路径随之变化，绕开资源管理器的图标缓存。
  Future<String> _writeShortcutIcon({
    required String gameId,
    required Uint8List bytes,
  }) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'shortcut_icons'));
    await dir.create(recursive: true);
    final stamp = sha256.convert(bytes).toString().substring(0, 8);
    final file = File(p.join(dir.path, 'astral_${gameId}_$stamp.ico'));
    if (!file.existsSync() || file.lengthSync() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }

  /// 把任意格式（PNG/JPEG/WebP…）的图片转成 256×256 的经典 BMP 图标。
  ///
  /// 不用 PNG-in-ICO：GDI 和部分外壳实现解析不了，快捷方式会显示空白。
  /// 结构：ICONDIR(6) + ICONDIRENTRY(16) + BITMAPINFOHEADER(40)
  ///       + 32bpp BGRA 位图（自下而上）+ 1bpp AND 掩码（全 0）。
  Uint8List? _buildIcoBytes(Uint8List raw) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return null;
      final side = decoded.width < decoded.height
          ? decoded.width
          : decoded.height;
      final cropped = img.copyCrop(
        decoded,
        x: (decoded.width - side) ~/ 2,
        y: (decoded.height - side) ~/ 2,
        width: side,
        height: side,
      );
      final resized = img.copyResize(
        cropped,
        width: 256,
        height: 256,
        interpolation: img.Interpolation.cubic,
      );

      const w = 256;
      const h = 256;
      const xorSize = w * h * 4;
      const andStride = ((w + 31) ~/ 32) * 4; // 每行按 32 位对齐
      const andSize = andStride * h;
      const dibSize = 40 + xorSize + andSize;

      final out = Uint8List(22 + dibSize);
      final bd = ByteData.sublistView(out);
      // ICO / BMP 头都是小端；ByteData 默认大端，必须显式指定。
      const le = Endian.little;

      // ICONDIR
      bd.setUint16(0, 0, le); // reserved
      bd.setUint16(2, 1, le); // type = icon
      bd.setUint16(4, 1, le); // count
      // ICONDIRENTRY
      bd.setUint8(6, 0); // 0 表示 256
      bd.setUint8(7, 0);
      bd.setUint8(8, 0); // color count
      bd.setUint8(9, 0); // reserved
      bd.setUint16(10, 1, le); // color planes
      bd.setUint16(12, 32, le); // bits per pixel
      bd.setUint32(14, dibSize, le);
      bd.setUint32(18, 22, le); // image offset

      // BITMAPINFOHEADER
      var o = 22;
      bd.setUint32(o, 40, le);
      o += 4;
      bd.setInt32(o, w, le);
      o += 4;
      bd.setInt32(o, h * 2, le); // XOR + AND 两段高度
      o += 4;
      bd.setUint16(o, 1, le); // planes
      o += 2;
      bd.setUint16(o, 32, le); // bpp
      o += 2;
      bd.setUint32(o, 0, le); // BI_RGB
      o += 4;
      bd.setUint32(o, xorSize, le);
      o += 4;
      o += 16; // x/y ppm、clrUsed、clrImportant

      // XOR 位图：BGRA，自下而上
      for (var y = h - 1; y >= 0; y--) {
        for (var x = 0; x < w; x++) {
          final px = resized.getPixel(x, y);
          out[o++] = px.b.toInt();
          out[o++] = px.g.toInt();
          out[o++] = px.r.toInt();
          out[o++] = px.a.toInt();
        }
      }
      // AND 掩码保持全 0（不透明），Uint8List 默认即 0
      return out;
    } catch (e) {
      appLogger.w('[Shortcut] 生成 ICO 失败: $e');
      return null;
    }
  }
}

class ShortcutException implements Exception {
  ShortcutException(this.message, {this.code});
  final String message;
  final ShortcutErrorCode? code;
  @override
  String toString() => message;
}

enum ShortcutErrorCode { noPermission, unsupported, desktopNotFound }
