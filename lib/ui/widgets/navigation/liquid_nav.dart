import 'dart:math' as math;

import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// 底栏与侧栏共用的“液体导航”物理控制器。
///
/// 把弹簧、拖拽吸附、按压抬起、跨项触感和 overscroll 收在一处，
/// 两个导航只负责各自轴向的几何，不再各写一套参数。
class LiquidNavController extends ChangeNotifier {
  LiquidNavController({
    required TickerProvider vsync,
    required this.count,
    required int initialIndex,
    required this.onSelected,
  }) : _currentIndex = initialIndex.clamp(0, math.max(0, count - 1)),
       _lastCrossing = initialIndex {
    position = AnimationController.unbounded(
      vsync: vsync,
      value: _currentIndex.toDouble(),
    );
    lift = AnimationController.unbounded(vsync: vsync);
    _listenable = Listenable.merge([position, lift, this]);
  }

  /// 相邻项点击：略带回弹，干净利落。
  static const _springTap = SpringDescription(
    mass: 1,
    stiffness: 700,
    damping: 30,
  );

  /// 跨多项 / 快速甩动：接近临界阻尼，避免顶到边缘后抽一下。
  static const _springJump = SpringDescription(
    mass: 1,
    stiffness: 640,
    damping: 40,
  );

  /// 系统开启“减少动态效果”：快速收敛，不做回弹。
  static const _springReduced = SpringDescription(
    mass: 1,
    stiffness: 1200,
    damping: 70,
  );

  /// 按下时指示器的轻微抬起。
  static const _springLift = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 24,
  );

  static const _maxDragVelocity = 6.0;

  /// 拖到首尾之外时允许的最大溢出（项），制造一点橡皮筋感。
  static const _maxOverscroll = 0.18;

  final int count;
  final ValueChanged<int> onSelected;

  /// 指示器位置，单位是“项”。允许短暂超出 0..count-1。
  late final AnimationController position;

  /// 0..1 的抬起程度，按压 / 拖拽时为 1。
  late final AnimationController lift;

  late final Listenable _listenable;

  int _currentIndex;
  int? _pressedIndex;
  bool _dragging = false;
  int _lastCrossing;
  bool _disposed = false;

  /// 系统“减少动态效果”开关，由 MediaQuery 注入。
  ///
  /// 直接写字段而不在 setter 里主动通知：调用点处在依赖变更阶段，
  /// 随后的 build 会读到新值。
  bool reduceMotion = false;

  Listenable get listenable => _listenable;

  int get currentIndex => _currentIndex;

  int? get pressedIndex => _pressedIndex;

  bool get dragging => _dragging;

  int get maxIndex => math.max(0, count - 1);

  /// 指示器实际绘制位置：给弹簧过冲留一点余量，但别让它跑太远。
  double get renderPosition =>
      position.value.clamp(-_maxOverscroll - 0.07, maxIndex + _maxOverscroll + 0.07);

  /// 离最近一项的距离，0 表示正好落在项上，1 表示最大拉伸。
  double get liquidAmount {
    if (reduceMotion) return 0;
    final gap = (renderPosition - renderPosition.round()).abs();
    return (gap / 0.5).clamp(0.0, 1.0);
  }

  /// 当前速度占最大拖拽速度的比例，用于按惯性额外拉长/压扁。
  double get velocityRatio {
    if (reduceMotion) return 0;
    return (position.velocity.abs() / _maxDragVelocity).clamp(0.0, 1.0);
  }

  double get liftAmount => reduceMotion ? 0 : lift.value.clamp(0.0, 1.2);

  /// 外部（Shell）切换 Tab 时同步选中项。
  void updateSelection(int index) {
    final target = index.clamp(0, maxIndex);
    if (target == _currentIndex) return;
    _currentIndex = target;
    _lastCrossing = target;
    _animateTo(target.toDouble(), _dragging ? 0 : position.velocity);
  }

  /// 点击导航项：重复点击也交给上层（回顶 / 关搜索），但不改选中。
  void tap(int index) {
    final target = index.clamp(0, maxIndex);
    if (target == _currentIndex) {
      onSelected(target);
      return;
    }
    HapticFeedback.selectionClick();
    onSelected(target);
  }

  void setPressed(int index, bool pressed) {
    final next = pressed ? index.clamp(0, maxIndex) : null;
    if (_pressedIndex == next) return;
    _pressedIndex = next;
    _animateLift(pressed ? 1 : 0);
    if (pressed) {
      // 按下就先把指示器弹向该项，不等手指抬起才动。
      _animateTo(next!.toDouble(), position.velocity);
    } else {
      _settleAfterRelease();
    }
    notifyListeners();
  }

  /// 开始拖拽：停掉进行中的弹簧，清掉残留的按压态，指示器立即跟手。
  void beginDrag(double rawPosition) {
    if (count < 2) return;
    position.stop();
    _dragging = true;
    _pressedIndex = null;
    _animateLift(1);
    position.value = _rubber(rawPosition);
    _lastCrossing = position.value.round();
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  void updateDrag(double rawPosition) {
    if (!_dragging) return;
    position.value = _rubber(rawPosition);
    final nearest = position.value.round();
    if (nearest == _lastCrossing) return;
    _lastCrossing = nearest;
    HapticFeedback.selectionClick();
  }

  /// 松手：吸附到最近的一项，并把拖动速度交给对应弹簧。
  void endDrag(double velocity) {
    if (!_dragging) return;
    final target = position.value.round().clamp(0, maxIndex);
    final changed = target != _currentIndex;
    _dragging = false;
    _animateLift(0);
    _animateTo(
      target.toDouble(),
      velocity.clamp(-_maxDragVelocity, _maxDragVelocity),
    );
    if (target != _lastCrossing) {
      _lastCrossing = target;
      HapticFeedback.selectionClick();
    }
    if (changed) {
      _currentIndex = target;
      _lastCrossing = target;
      onSelected(target);
    }
    notifyListeners();
  }

  /// 松手后如果并没有切换选中（手势取消），再弹回当前项。
  void _settleAfterRelease() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _dragging || _pressedIndex != null) return;
      final nearest = position.value.round().clamp(0, maxIndex);
      if (nearest == _currentIndex) return;
      _animateTo(_currentIndex.toDouble(), position.velocity);
    });
  }

  void _animateTo(double target, double velocity) {
    if (_disposed) return;
    final distance = (target - position.value).abs();
    final spring = reduceMotion ? _springReduced : _springFor(distance, velocity);
    position.animateWith(
      SpringSimulation(spring, position.value, target, velocity),
    );
  }

  static SpringDescription _springFor(double distance, double velocity) {
    if (distance > 1.15 || velocity.abs() > 2.5) return _springJump;
    return _springTap;
  }

  void _animateLift(double target) {
    if (_disposed || reduceMotion) return;
    lift.animateWith(
      SpringSimulation(_springLift, lift.value, target, lift.velocity),
    );
  }

  /// 首尾之外按 0.35 的系数衰减，保留一点橡皮筋手感。
  double _rubber(double raw) {
    final max = maxIndex.toDouble();
    if (reduceMotion) return raw.clamp(0.0, max);
    if (raw < 0) return -math.min(_maxOverscroll, -raw * 0.35);
    if (raw > max) {
      return max + math.min(_maxOverscroll, (raw - max) * 0.35);
    }
    return raw;
  }

  @override
  void dispose() {
    _disposed = true;
    position.dispose();
    lift.dispose();
    super.dispose();
  }
}

/// 液体指示器的绘制层：位置/形变/按压全部走绘制，不触发每帧布局。
///
/// [axis] 决定沿哪根轴拉伸：底栏水平、侧栏垂直。
class LiquidNavPainter extends CustomPainter {
  LiquidNavPainter({
    required this.axis,
    required this.center,
    required this.crossExtent,
    required this.baseLength,
    required this.lengthFactor,
    required this.crossFactor,
    required this.lift,
    required this.palette,
  });

  final Axis axis;

  /// 沿轴的中心坐标。
  final double center;

  /// 横轴方向的基准尺寸：水平导航是高度，垂直导航是宽度。
  final double crossExtent;

  /// 沿轴方向的基准长度。
  final double baseLength;

  final double lengthFactor;
  final double crossFactor;

  /// 0..1.2 的抬起程度。
  final double lift;

  final AppThemePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final length = math.max(1.0, baseLength * lengthFactor);
    final cross = math.max(1.0, crossExtent * crossFactor);
    final width = axis == Axis.horizontal ? length : cross;
    final height = axis == Axis.horizontal ? cross : length;
    final cx = axis == Axis.horizontal ? center : size.width / 2;
    final cy = axis == Axis.horizontal ? size.height / 2 : center;
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: width,
      height: height,
    );

    final scale = 1 + 0.08 * lift.clamp(0.0, 1.2);
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale, scale);
    canvas.translate(-cx, -cy);

    final radius = math.min(width, height) / 2;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // 投影画在填充之前，阅读成“液滴浮在玻璃上”；按压时抬得更高。
    final shadowPaint = Paint()
      ..color = palette.shadowSoft
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        8 + 6 * lift.clamp(0.0, 1.0),
      );
    canvas.drawRRect(rrect.shift(Offset(0, 2 + 2 * lift)), shadowPaint);

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [palette.accentMutedStrong, palette.accentMuted],
      ).createShader(rect);
    canvas.drawRRect(rrect, fill);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = palette.accent.withValues(alpha: 0.12);
    canvas.drawRRect(rrect, border);

    // 顶部一道极轻的高光，给半透明色块一点“有厚度”的暗示。
    final inset = radius * 0.7;
    final sheenRect = Rect.fromLTWH(
      rect.left + inset,
      rect.top + 1.2,
      math.max(0, rect.width - inset * 2),
      1.2,
    );
    if (sheenRect.width > 1) {
      final sheen = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.22),
            Colors.transparent,
          ],
        ).createShader(sheenRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(sheenRect, const Radius.circular(1)),
        sheen,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LiquidNavPainter oldDelegate) {
    return oldDelegate.axis != axis ||
        oldDelegate.center != center ||
        oldDelegate.crossExtent != crossExtent ||
        oldDelegate.baseLength != baseLength ||
        oldDelegate.lengthFactor != lengthFactor ||
        oldDelegate.crossFactor != crossFactor ||
        oldDelegate.lift != lift ||
        oldDelegate.palette != palette;
  }
}
