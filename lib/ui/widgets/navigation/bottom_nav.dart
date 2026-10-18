import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/glass_capsule.dart';
import 'package:astral_game/ui/widgets/navigation/navigation_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// 悬浮胶囊式底部导航：选中指示器用弹簧动画滑动，图标随距离渐变；
/// 按住胶囊可直接左右拖动切换，松手吸附到最近的 Tab。
///
/// 液态观感由三部分组成：
/// * 半透明磨砂玻璃胶囊（[BackdropFilter] + 高光描边）；
/// * 指示器在两 Tab 之间被“拉长压扁”，回到 Tab 时再回弹成胶囊；
/// * 按住时指示器与图标轻微放大，松手弹簧回弹。
///
/// 传入 [trailingActions] 时，右侧会展开同款玻璃行动胶囊，
/// 导航胶囊随之向左收缩（类似 Apple 悬浮底栏的搜索占位）。
class BottomNav extends StatefulWidget {
  const BottomNav({
    super.key,
    required this.navigationItems,
    required this.selectedIndex,
    required this.onSelected,
    this.trailingActions = const [],
  });

  final List<NavigationItem> navigationItems;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 右侧行动胶囊里的操作；为空时收起到 0 宽。
  final List<BottomNavAction> trailingActions;

  @override
  State<BottomNav> createState() => _BottomNavState();
}

/// 悬浮底栏右侧行动胶囊里的一个操作。
class BottomNavAction {
  const BottomNavAction({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.loading = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  /// 进行中：图标换成小号 spinner，按钮不可点。
  final bool loading;
}

class _BottomNavState extends State<BottomNav> with TickerProviderStateMixin {
  /// 带回弹的弹簧：按下/切换时略冲一点再弹回来，Q 但不晃。
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 460,
    damping: 19,
  );

  /// 拖动结束时的最大初速度（Tab/s），避免快速甩动时弹簧冲得太远。
  static const _maxDragVelocity = 6.0;

  /// 指示器被拉长的最大比例（位于两个 Tab 正中间时）。
  static const _maxStretch = 0.30;

  /// 拉长时竖向被压扁的最大比例，体积守恒，像一滴液体。
  static const _maxSquash = 0.14;

  late final AnimationController _position;

  late int _currentIndex;

  /// 行动胶囊当前承载的操作。
  ///
  /// 收起到 0 宽的过程中继续沿用最后一组非空操作，让玻璃是被宽度裁掉，
  /// 而不是内容先瞬间消失。
  List<BottomNavAction> _visibleActions = const [];

  /// 正在拖动：指示器跟手并放大。
  bool _dragging = false;

  /// 当前按住的项（未松手），用于按压放大反馈。
  int? _pressedIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.selectedIndex;
    _position = AnimationController.unbounded(
      vsync: this,
      value: _currentIndex.toDouble(),
    );
    _visibleActions = widget.trailingActions;
  }

  @override
  void didUpdateWidget(covariant BottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trailingActions.isNotEmpty) {
      _visibleActions = widget.trailingActions;
    }
    if (widget.selectedIndex == _currentIndex) return;
    _currentIndex = widget.selectedIndex;
    _position.animateWith(
      SpringSimulation(
        _spring,
        _position.value,
        _currentIndex.toDouble(),
        _position.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  /// 开始拖动：停掉进行中的弹簧，指示器立即吸附到手指下方。
  void _beginDrag(double dx, double itemWidth, int count) {
    _position.stop();
    if (count < 2) return;
    _dragTo(dx, itemWidth, count);
    if (_dragging) return;
    setState(() => _dragging = true);
  }

  /// 指示器中心跟到手指下方。
  void _updateDrag(double dx, double itemWidth, int count) {
    if (count < 2) return;
    _dragTo(dx, itemWidth, count);
  }

  void _dragTo(double dx, double itemWidth, int count) {
    final raw = dx / itemWidth - 0.5;
    _position.value = raw.clamp(0.0, (count - 1).toDouble());
  }

  /// 松手：吸附到最近的 Tab，并把拖动速度交给弹簧。
  void _endDrag(double velocity, int count) {
    if (count == 0) return;
    final target = _position.value.round().clamp(0, count - 1);
    final changed = target != _currentIndex;
    _currentIndex = target;
    setState(() {
      _dragging = false;
      _pressedIndex = null;
    });
    _position.animateWith(
      SpringSimulation(
        _spring,
        _position.value,
        target.toDouble(),
        velocity.clamp(-_maxDragVelocity, _maxDragVelocity),
      ),
    );
    if (!changed) return;
    HapticFeedback.selectionClick();
    widget.onSelected(target);
  }

  void _setPressed(int index, bool pressed) {
    final next = pressed ? index : null;
    if (_pressedIndex == next) return;
    setState(() => _pressedIndex = next);
    if (pressed) {
      // 按下就先把指示器弹向该 Tab，不等手指抬起才动。
      _springTo(index);
      return;
    }
    // 松手后如果并没有切换选中（手势取消），再弹回当前 Tab。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dragging || _pressedIndex != null) return;
      if (widget.selectedIndex != index) _springTo(_currentIndex);
    });
  }

  /// 用同一套弹簧把指示器送到 [target]。
  void _springTo(int target) {
    if (_dragging) return;
    _position.animateWith(
      SpringSimulation(
        _spring,
        _position.value,
        target.toDouble(),
        _position.velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final size = MediaQuery.sizeOf(context);
    final isSmallWindow = size.width < 320 || size.height < 420;

    final barHeight = isSmallWindow ? 56.0 : 64.0;

    // 行动胶囊的自然宽度：宽度动画的终点，也是玻璃裁剪的基准。
    final targetTrailingWidth = _trailingWidth(
      widget.trailingActions,
      barHeight,
    );

    // 展开时与导航胶囊之间的间隙也参与宽度动画。
    //
    // 如果把它留作固定的 Padding，胶囊缩到 0 的最后一帧会一次性跳掉这段距离，
    // 看起来就是“卡一下”。
    const trailingGap = 12.0;
    final targetSlotWidth = targetTrailingWidth == 0
        ? 0.0
        : targetTrailingWidth + trailingGap;

    return Padding(
      // 上下对称留出间隙，避免胶囊与内容边缘贴死、看起来像盖住了内容。
      padding: EdgeInsets.fromLTRB(20, 10, 20, isSmallWindow ? 6 : 10),
      child: Row(
        children: [
          Expanded(
            child: GlassCapsule(
              radius: BorderRadius.circular(32),
              child: Material(
                type: MaterialType.transparency,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final count = widget.navigationItems.length;
                    if (count == 0) return const SizedBox.shrink();
                    final itemWidth = constraints.maxWidth / count;
                    final height = isSmallWindow ? 56.0 : 64.0;
                    final showLabels = !isSmallWindow && itemWidth >= 56;

                    return SizedBox(
                      height: height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // 按住后左右拖动：指示器跟手，松手吸附到最近的 Tab。
                        onHorizontalDragStart: (details) => _beginDrag(
                          details.localPosition.dx,
                          itemWidth,
                          count,
                        ),
                        onHorizontalDragUpdate: (details) => _updateDrag(
                          details.localPosition.dx,
                          itemWidth,
                          count,
                        ),
                        onHorizontalDragEnd: (details) => _endDrag(
                          details.velocity.pixelsPerSecond.dx / itemWidth,
                          count,
                        ),
                        onHorizontalDragCancel: () => _endDrag(0, count),
                        child: AnimatedBuilder(
                          animation: _position,
                          builder: (context, _) {
                            final position = _position.value.clamp(
                              0.0,
                              (count - 1).toDouble(),
                            );
                            // 离最近的 Tab 越远，液滴拉得越长；回到 Tab 复原。
                            final gap = (position - position.round()).abs();
                            final liquid = (gap / 0.5).clamp(0.0, 1.0);
                            final active = _dragging || _pressedIndex != null;
                            final press = active ? 1.08 : 1.0;

                            final baseWidth = itemWidth - 12;
                            final blobWidth =
                                baseWidth * (1 + _maxStretch * liquid);
                            final blobHeight =
                                (height - 12) * (1 - _maxSquash * liquid);
                            final center = position * itemWidth + itemWidth / 2;

                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // 选中指示器：位置由弹簧动画驱动，宽度随距离拉伸。
                                Positioned(
                                  left: center - blobWidth / 2,
                                  top: (height - blobHeight) / 2,
                                  width: blobWidth,
                                  height: blobHeight,
                                  child: AnimatedScale(
                                    scale: press,
                                    duration: const Duration(milliseconds: 240),
                                    curve: Curves.easeOutBack,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: palette.accentMuted,
                                        borderRadius: BorderRadius.circular(
                                          blobHeight,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    for (var i = 0; i < count; i++)
                                      Expanded(
                                        child: _NavItem(
                                          item: widget.navigationItems[i],
                                          selected: i == _currentIndex,
                                          selectedness:
                                              (1 - (position - i).abs()).clamp(
                                                0.0,
                                                1.0,
                                              ),
                                          showLabel: showLabels,
                                          pressed: _pressedIndex == i,
                                          onPressedChanged: (pressed) =>
                                              _setPressed(i, pressed),
                                          onTap: () => widget.onSelected(i),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // 右侧行动占位：与左侧导航在同一条布局链里，用真实宽度驱动动画，
          // 两侧像同一块玻璃被拉伸/压缩，而不是两个胶囊一进一出。
          //
          // 动画的是“整段占位宽度”（含间隙），玻璃宽度在内部扣除间隙后计算：
          // 收起时玻璃先缩到 0，间隙再一起收掉，全程没有固定 padding 突然消失。
          //
          // 玻璃自身按动画宽度裁剪内容（[OverflowBox] 让内容保持自然宽度并右对齐），
          // 投影画在裁剪之外，所以不会被裁成方块。
          SizedBox(
            height: barHeight,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: targetSlotWidth,
                end: targetSlotWidth,
              ),
              // 与 Tab 淡入同时长：收起/展开和页面切换是同一次动作。
              duration: const Duration(
                milliseconds: AppDimensions.fadeDurationMs,
              ),
              curve: Curves.easeOutCubic,
              // 内容作为 child 传入：宽度动画每帧只重建几何，
              // 不重建玻璃里的按钮，避免动画期间的无谓开销和按压状态丢失。
              child: IgnorePointer(
                // 收起过程中沿用上一组内容，但不应还能点到已离开页面的操作。
                ignoring: widget.trailingActions.isEmpty,
                child: _ActionCapsuleContent(
                  height: barHeight,
                  actions: _visibleActions,
                ),
              ),
              builder: (context, slotWidth, child) {
                if (slotWidth < 0.5) return const SizedBox.shrink();
                final glassWidth = (slotWidth - trailingGap).clamp(
                  0.0,
                  double.infinity,
                );
                return SizedBox(
                  width: slotWidth,
                  height: barHeight,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: glassWidth < 0.5
                        ? const SizedBox.shrink()
                        : SizedBox(
                            width: glassWidth,
                            height: barHeight,
                            child: GlassCapsule(
                              radius: BorderRadius.circular(barHeight),
                              child: OverflowBox(
                                alignment: Alignment.centerRight,
                                minWidth: 0,
                                maxWidth: double.infinity,
                                child: child,
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 行动胶囊在给定高度下的自然宽度：单个操作是圆形，多个操作并成一枚胶囊。
double _trailingWidth(List<BottomNavAction> actions, double height) {
  if (actions.isEmpty) return 0;
  if (actions.length == 1) return height;
  final itemWidth = height - 20;
  return 4 + 4 + actions.length * itemWidth + (actions.length - 1) * 0.8;
}

/// 行动胶囊的内容：按操作数量自然排布，宽度由外层玻璃动画裁剪。
class _ActionCapsuleContent extends StatelessWidget {
  const _ActionCapsuleContent({required this.height, required this.actions});

  final double height;
  final List<BottomNavAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return SizedBox(height: height);
    if (actions.length == 1) {
      return SizedBox(
        width: height,
        height: height,
        child: _CapsuleAction(action: actions.first),
      );
    }

    final palette = context.astralPalette;
    final itemWidth = height - 20;

    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 4),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0)
              Container(width: 0.8, height: 22, color: palette.divider),
            SizedBox(
              width: itemWidth,
              height: height,
              child: _CapsuleAction(action: actions[i]),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _CapsuleAction extends StatelessWidget {
  const _CapsuleAction({required this.action});

  final BottomNavAction action;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final enabled = action.onPressed != null;
    final overlay = enabled ? palette.accent : palette.textTertiary;
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: action.tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: action.onPressed,
          // 槽位是 44×64 的矩形，StadiumBorder 会按短边半径画成一根竖椭圆。
          // 圆形按钮的高亮应当是正圆：CircleBorder 内切到短边，直径等于槽宽。
          customBorder: const CircleBorder(),
          // 桌面端点击后 InkWell 会保留键盘焦点，默认 focusColor 是 12% 黑，
          // 在浅色玻璃上会留下一整块灰色圆盘，看起来像玻璃里又嵌了一个按钮。
          // 这里统一成跟玻璃同调的极轻高亮，露出一枚完整玻璃的观感。
          focusColor: overlay.withValues(alpha: 0.06),
          hoverColor: overlay.withValues(alpha: 0.04),
          splashColor: overlay.withValues(alpha: 0.05),
          highlightColor: Colors.transparent,
          child: Center(child: _ActionIcon(action: action, size: 21)),
        ),
      ),
    );
    final tooltip = action.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.action, required this.size});

  final BottomNavAction action;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (action.loading) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final palette = context.astralPalette;
    return Icon(
      action.icon,
      size: size,
      color: action.onPressed == null
          ? palette.textTertiary
          : palette.textSecondary,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.selectedness,
    required this.showLabel,
    required this.pressed,
    required this.onPressedChanged,
    required this.onTap,
  });

  final NavigationItem item;
  final bool selected;
  final double selectedness;
  final bool showLabel;

  /// 按住时图标轻微放大，松手回弹。
  final bool pressed;
  final ValueChanged<bool> onPressedChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final iconColor = Color.lerp(
      palette.textTertiary,
      palette.accent,
      selectedness,
    )!;
    final labelColor = Color.lerp(
      palette.textSecondary,
      palette.accent,
      selectedness,
    )!;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        onHighlightChanged: onPressedChanged,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(32),
        // 与行动胶囊一致：玻璃上只用极轻的主题色高亮，
        // 避免默认焦点色在玻璃里留下灰色方块。
        focusColor: palette.accent.withValues(alpha: 0.06),
        hoverColor: palette.accent.withValues(alpha: 0.04),
        // 不要 Material 自带的按压水波纹：按压反馈只保留图标放大 + 指示器跟手。
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedScale(
          scale: pressed ? 1.10 : 1.0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutBack,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? item.activeIcon : item.icon,
                size: 22 + 2 * selectedness,
                color: iconColor,
              ),
              if (showLabel) ...[
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: labelColor,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
