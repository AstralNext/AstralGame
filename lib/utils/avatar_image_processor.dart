import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 头像图片的基本信息。
class AvatarImageInfo {
  const AvatarImageInfo({
    required this.width,
    required this.height,
    required this.animated,
  });

  final int width;
  final int height;

  /// 是否为动图（GIF / 动态 WebP）。
  final bool animated;
}

/// 头像编辑所需的图片处理：读取尺寸、判定动图、按裁剪框输出头像。
abstract final class AvatarImageProcessor {
  /// 头像体积上限（2MB）。
  static const maxBytes = 2 * 1024 * 1024;

  /// 原图软上限：超过直接拒绝，避免解码超大文件占用过多内存。
  /// 相机原图通常 2~8MB，裁剪后会重新编码成 320px，远小于 [maxBytes]。
  static const maxInputBytes = 20 * 1024 * 1024;

  /// 输出头像边长；正方形，足够覆盖所有头像位置在高分屏上的显示。
  static const outputSize = 320;

  /// 读取图片尺寸并判断是否为动图。
  static Future<AvatarImageInfo?> inspect(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final info = AvatarImageInfo(
        width: frame.image.width,
        height: frame.image.height,
        animated: codec.frameCount > 1,
      );
      frame.image.dispose();
      codec.dispose();
      return info;
    } catch (_) {
      return null;
    }
  }

  /// 按原图像素坐标 [sourceRect] 裁出正方形头像。
  ///
  /// 动图逐帧裁剪后重新编码为 GIF，保留动画；静态图走 Flutter 原生编解码，
  /// 输出 PNG。结果仍可能超过 [maxBytes]，由调用方校验。
  static Future<Uint8List> crop(
    Uint8List bytes, {
    required AvatarImageInfo info,
    required ui.Rect sourceRect,
  }) async {
    // 取整并夹回图片范围内，避免取样越界出现透明边。
    final side = sourceRect.width.round().clamp(
      1,
      math.min(info.width, info.height),
    );
    final x = sourceRect.left.round().clamp(0, info.width - side);
    final y = sourceRect.top.round().clamp(0, info.height - side);

    if (info.animated) {
      return compute(_cropAnimated, <String, Object>{
        'bytes': bytes,
        'x': x,
        'y': y,
        'side': side,
      });
    }

    return _cropStill(
      bytes,
      ui.Rect.fromLTWH(
        x.toDouble(),
        y.toDouble(),
        side.toDouble(),
        side.toDouble(),
      ),
    );
  }

  static Future<Uint8List> _cropStill(Uint8List bytes, ui.Rect rect) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final side = outputSize.toDouble();
    canvas.drawImageRect(
      source,
      rect,
      ui.Rect.fromLTWH(0, 0, side, side),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.high
        ..isAntiAlias = true,
    );

    final picture = recorder.endRecording();
    final output = await picture.toImage(outputSize, outputSize);
    picture.dispose();
    source.dispose();
    codec.dispose();

    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    output.dispose();
    return data!.buffer.asUint8List();
  }
}

/// 动图逐帧裁剪并重新编码为 GIF。
///
/// 放在 isolate 里跑，避免大图解码阻塞 UI。
Uint8List _cropAnimated(Map<String, Object> args) {
  final bytes = args['bytes']! as Uint8List;
  final x = args['x']! as int;
  final y = args['y']! as int;
  final side = args['side']! as int;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final frames = <img.Image>[];
  for (final frame in decoded.frames) {
    final cropped = img.copyCrop(frame, x: x, y: y, width: side, height: side);
    frames.add(
      img.copyResize(
        cropped,
        width: AvatarImageProcessor.outputSize,
        height: AvatarImageProcessor.outputSize,
        interpolation: img.Interpolation.average,
      ),
    );
  }

  final output = frames.first;
  for (var i = 1; i < frames.length; i++) {
    output.addFrame(frames[i]);
  }
  output.loopCount = decoded.loopCount;

  return Uint8List.fromList(img.encodeGif(output));
}
