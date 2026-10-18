import 'dart:math' as math;
import 'dart:typed_data';

import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/app_toast.dart';
import 'package:astral_game/utils/avatar_image_processor.dart';
import 'package:flutter/material.dart';

/// 打开头像编辑器：可拖动、缩放并裁剪，动图保留动画。
///
/// 返回处理后的头像字节；取消返回 null。
Future<Uint8List?> showAvatarEditor(
  BuildContext context, {
  required Uint8List bytes,
  required AvatarImageInfo info,
}) {
  return showDialog<Uint8List>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (_) => _AvatarEditorDialog(bytes: bytes, info: info),
  );
}

class _AvatarEditorDialog extends StatefulWidget {
  const _AvatarEditorDialog({required this.bytes, required this.info});

  final Uint8List bytes;
  final AvatarImageInfo info;

  @override
  State<_AvatarEditorDialog> createState() => _AvatarEditorDialogState();
}

class _AvatarEditorDialogState extends State<_AvatarEditorDialog> {
  static const _minScale = 1.0;
  static const _maxScale = 4.0;

  double _scale = _minScale;
  Offset _offset = Offset.zero;
  double _startScale = _minScale;

  /// 裁剪窗口边长与图片按「铺满」缩放后的基准尺寸，由布局阶段写入。
  double _viewportSide = 0;
  double _baseWidth = 0;
  double _baseHeight = 0;

  bool _processing = false;

  /// 双指缩放 / 拖动后重新夹紧位移，保证图片始终铺满裁剪窗口。
  void _updateTransform({required double scale, required Offset offset}) {
    final maxDx = math.max(0.0, (_baseWidth * scale - _viewportSide) / 2);
    final maxDy = math.max(0.0, (_baseHeight * scale - _viewportSide) / 2);
    setState(() {
      _scale = scale;
      _offset = Offset(
        offset.dx.clamp(-maxDx, maxDx),
        offset.dy.clamp(-maxDy, maxDy),
      );
    });
  }

  Future<void> _confirm() async {
    if (_processing) return;
    setState(() => _processing = true);

    // 由当前缩放与位移反推裁剪窗口覆盖的原图区域。
    final info = widget.info;
    final totalScale = _baseScale * _scale;
    final side = _viewportSide / totalScale;
    final left =
        (_baseWidth * _scale / 2 - _viewportSide / 2 - _offset.dx) / totalScale;
    final top =
        (_baseHeight * _scale / 2 - _viewportSide / 2 - _offset.dy) /
        totalScale;

    final maxLeft = math.max(0.0, info.width - side);
    final maxTop = math.max(0.0, info.height - side);
    final sourceRect = Rect.fromLTWH(
      left.clamp(0.0, maxLeft),
      top.clamp(0.0, maxTop),
      side,
      side,
    );

    try {
      final result = await AvatarImageProcessor.crop(
        widget.bytes,
        info: info,
        sourceRect: sourceRect,
      );
      if (!mounted) return;
      if (result.length > AvatarImageProcessor.maxBytes) {
        setState(() => _processing = false);
        showAppToast(context, '处理后的头像超过 2MB，请换一张图片');
        return;
      }
      Navigator.pop(context, result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _processing = false);
      showAppToast(context, '图片处理失败，请重试');
    }
  }

  /// 图片按「铺满窗口」的比例，基准尺寸即在此比例下的像素尺寸。
  double get _baseScale => math.max(
    _viewportSide / widget.info.width,
    _viewportSide / widget.info.height,
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: palette.shadowLift,
                blurRadius: 48,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '编辑头像',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.info.animated
                      ? '拖动调整位置，双指或滑杆缩放，动图会保留动画'
                      : '拖动调整位置，双指或滑杆缩放',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                // 宽而矮的窗口里，正方形裁剪区会把内容撑出屏幕：
                // 用 Flexible 让它在剩余高度内等比缩小，而不是溢出。
                Flexible(
                  child: Center(
                    child: AspectRatio(aspectRatio: 1, child: _buildViewport()),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.zoom_out_rounded,
                      size: 18,
                      color: palette.textTertiary,
                    ),
                    Expanded(
                      child: Slider(
                        value: _scale,
                        min: _minScale,
                        max: _maxScale,
                        activeColor: palette.accent,
                        inactiveColor: palette.canvas,
                        onChanged: (value) =>
                            _updateTransform(scale: value, offset: _offset),
                      ),
                    ),
                    Icon(
                      Icons.zoom_in_rounded,
                      size: 18,
                      color: palette.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _processing
                            ? null
                            : () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: palette.textSecondary,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _processing ? null : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor: palette.onAccent,
                          disabledBackgroundColor: palette.accent.withValues(
                            alpha: 0.5,
                          ),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: _processing
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.onAccent,
                                ),
                              )
                            : const Text('完成'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewport() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 布局阶段同步裁剪几何，滑杆与手势都依赖它。
        _viewportSide = constraints.maxWidth;
        _baseWidth = widget.info.width * _baseScale;
        _baseHeight = widget.info.height * _baseScale;

        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ColoredBox(
            color: Colors.black,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) {
                _startScale = _scale;
              },
              onScaleUpdate: (details) {
                final scale = (_startScale * details.scale).clamp(
                  _minScale,
                  _maxScale,
                );
                _updateTransform(
                  scale: scale,
                  offset: _offset + details.focalPointDelta,
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Center 会把子级约束在窗口尺寸内，放大后的 SizedBox 会被压回
                  // 原尺寸，预览看着不动；OverflowBox 让图片可以真实超出窗口。
                  OverflowBox(
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: Transform.translate(
                      offset: _offset,
                      child: SizedBox(
                        width: _baseWidth * _scale,
                        height: _baseHeight * _scale,
                        child: Image.memory(
                          widget.bytes,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                  const IgnorePointer(
                    child: CustomPaint(painter: _CropMaskPainter()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 裁剪蒙层：圆形窗口外压暗并描边。
class _CropMaskPainter extends CustomPainter {
  const _CropMaskPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final circle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: size.shortestSide / 2));
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      circle,
    );

    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );
    canvas.drawPath(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_CropMaskPainter oldDelegate) => false;
}
