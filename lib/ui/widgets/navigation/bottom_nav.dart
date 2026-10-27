import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/glass_capsule.dart';
import 'package:astral_game/ui/widgets/navigation/liquid_nav.dart';
import 'package:astral_game/ui/widgets/navigation/navigation_item.dart';
import 'package:flutter/material.dart';

/// 悬浮胶囊式底部导航：选中指示器用弹簧动画滑动，图标随距离渐变；
/// 按住胶囊可直接左右拖动切换，松手吸附到最近的 Tab。
///
/// 液态观感由三部分组成：
/// * 半透明磨砂玻璃胶囊（[BackdropFilter] + 高光描边）；
/// * 指示器在两 Tab 之间被“拉长压扁”，并按速度做非对称拖尾；
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
    this.statusDots = const <int>{},
  });

  final List<NavigationItem> navigationItems;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 右侧行动胶囊里的操作；为空时收起到 0 宽。
  final List<BottomNavAction> trailingActions;

  /// 需要显示状态点的导航项索引（例如联机中）。
  final Set<int> statusDots;

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

  /// 进行中：图标持续旋转，按钮不可点。
  final bool loading;
}

class _BottomNavState extends State<BottomNav> with TickerProviderStateMixin {
  /// 指示器被拉长的最大比例（位于两个 Tab 正中间时）。
  static const _maxStretch = 0.30;

  /// 拉长时竖向被压扁的最大比例，体积守恒，像一滴液体。
  static const _maxSquash = 0.14;

  late final LiquidNavController _liquid;

  @override
  void initState() {
    super.initState();
    _liquid = LiquidNavController(
      vsync: this,
      count: widget.navigationItems.length,
      initialIndex: widget.selectedIndex,
      onSelected: (index) => widget.onSelected(index),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _liquid.reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant BottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    _liquid.updateSelection(widget.selectedIndex);
  }

  @override
  void dispose() {
    _liquid.dispose();
    super.dispose();
  }

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;

  /// 把手指的横向坐标换算成“第几项”，RTL 时从右向左。
  double _dragPosition(double dx, double itemWidth, double barWidth) {
    final x = _isRtl ? barWidth - dx : dx;
    return x / itemWidth - 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final size = MediaQuery.sizeOf(context);
    final isSmallWindow = size.width < 320 || size.height < 420;
    final reduceMotion = _liquid.reduceMotion;
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;

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
                    const height = 64.0;
                    // 用“动画终点”的稳定宽度决定标签是否可能显示，
                    // 避免行动胶囊收缩时标签整批闪现/消失。
                    final stableItemWidth =
                        (size.width - 40 - targetSlotWidth) / count;
                    final labelsCapable =
                        !isSmallWindow &&
                        stableItemWidth >= 54 &&
                        textScale < 1.8;
                    // 宽度动画过程中让标签连续淡入淡出，图标位移也跟随，
                    // 不再从 64 高度瞬间跳成 24。
                    final labelScaleFade = ((2.0 - textScale) / 0.5).clamp(
                      0.0,
                      1.0,
                    );
                    final labelProgress = labelsCapable
                        ? ((itemWidth - 50) / 14).clamp(0.0, 1.0) *
                              labelScaleFade
                        : 0.0;

                    return SizedBox(
                      height: isSmallWindow ? 56.0 : height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // 按住后左右拖动：指示器跟手，松手吸附到最近的 Tab。
                        onHorizontalDragStart: (details) => _liquid.beginDrag(
                          _dragPosition(
                            details.localPosition.dx,
                            itemWidth,
                            constraints.maxWidth,
                          ),
                        ),
                        onHorizontalDragUpdate: (details) => _liquid.updateDrag(
                          _dragPosition(
                            details.localPosition.dx,
                            itemWidth,
                            constraints.maxWidth,
                          ),
                        ),
                        onHorizontalDragEnd: (details) {
                          final velocity =
                              details.velocity.pixelsPerSecond.dx / itemWidth;
                          _liquid.endDrag(_isRtl ? -velocity : velocity);
                        },
                        onHorizontalDragCancel: () => _liquid.endDrag(0),
                        child: AnimatedBuilder(
                          animation: _liquid.listenable,
                          builder: (context, _) {
                            final barHeight = isSmallWindow ? 56.0 : height;
                            final position = _liquid.renderPosition;
                            final liquid = _liquid.liquidAmount;
                            final speed = _liquid.velocityRatio;
                            final direction = _liquid.position.velocity.sign;
                            // 距离决定基础拉伸，速度额外拉出一点尾巴。
                            final stretch =
                                _maxStretch *
                                    liquid *
                                    (_liquid.dragging ? 1.0 : 0.78) +
                                0.18 * speed;
                            final squash = _maxSquash * liquid + 0.10 * speed;
                            final baseWidth = itemWidth - 12;
                            final baseHeight = barHeight - 12;
                            final rawCenter =
                                position * itemWidth +
                                itemWidth / 2 -
                                direction * itemWidth * 0.02 * speed;
                            final center = _isRtl
                                ? constraints.maxWidth - rawCenter
                                : rawCenter;

                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // 指示器只走绘制：位置、拉伸、按压都不触发布局。
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: LiquidNavPainter(
                                        axis: Axis.horizontal,
                                        center: center,
                                        crossExtent: baseHeight,
                                        baseLength: baseWidth,
                                        lengthFactor: 1 + stretch,
                                        crossFactor: 1 - squash,
                                        lift: _liquid.liftAmount,
                                        palette: palette,
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
                                          selected:
                                              i == widget.selectedIndex,
                                          selectedness:
                                              (1 - (position - i).abs()).clamp(
                                                0.0,
                                                1.0,
                                              ),
                                          labelProgress: labelProgress,
                                          labelsCapable: labelsCapable,
                                          pressed:
                                              _liquid.pressedIndex == i &&
                                              !reduceMotion,
                                          showStatusDot: widget.statusDots
                                              .contains(i),
                                          onPressedChanged: (pressed) =>
                                              _liquid.setPressed(i, pressed),
                                          onTap: () => _liquid.tap(i),
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
              // 与页面切换共用同一时基：收起/展开和页面是同一次动作。
              duration: Duration(
                milliseconds: reduceMotion
                    ? 1
                    : AppDimensions.tabTransitionMs,
              ),
              curve: Curves.easeOutCubic,
              // 内容作为 child 传入：宽度动画每帧只重建几何，
              // 不重建玻璃里的按钮，避免动画期间的无谓开销和按压状态丢失。
              child: IgnorePointer(
                // 收起过程中不应还能点到已离开页面的操作。
                ignoring: widget.trailingActions.isEmpty,
                child: _ActionCapsuleContent(
                  height: barHeight,
                  actions: widget.trailingActions,
                  reduceMotion: reduceMotion,
                ),
              ),
              builder: (context, slotWidth, child) {
                if (slotWidth < 0.5) return const SizedBox.shrink();
                final glassWidth = (slotWidth - trailingGap).clamp(
                  0.0,
                  double.infinity,
                );
                final animating = (slotWidth - targetSlotWidth).abs() > 0.5;
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
                              // 宽度动画期间降低模糊，减少每帧重新采样背景。
                              sigma: animating
                                  ? GlassCapsule.animatingBlurSigma
                                  : GlassCapsule.blurSigma,
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
///
/// 操作集合变化时用淡入 + 轻微缩放交叉切换，避免按钮“突然换人”。
class _ActionCapsuleContent extends StatelessWidget {
  const _ActionCapsuleContent({
    required this.height,
    required this.actions,
    required this.reduceMotion,
  });

  final double height;
  final List<BottomNavAction> actions;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final signature = actions.isEmpty
        ? 'empty'
        : actions.map((action) => action.icon.codePoint).join('-');

    return AnimatedSwitcher(
      duration: Duration(milliseconds: reduceMotion ? 1 : 140),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerRight,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            alignment: Alignment.centerRight,
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(signature),
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (actions.isEmpty) return SizedBox(width: 0, height: height);
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

/// 行动图标：进行中不再换成小 spinner（会带来布局跳变），
/// 而是让原图标原地连续旋转，保持同一枚按钮的连续性。
class _ActionIcon extends StatefulWidget {
  const _ActionIcon({required this.action, required this.size});

  final BottomNavAction action;
  final double size;

  @override
  State<_ActionIcon> createState() => _ActionIconState();
}

class _ActionIconState extends State<_ActionIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant _ActionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpin();
  }

  void _syncSpin() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (widget.action.loading && !reduceMotion) {
      if (!_spin.isAnimating) _spin.repeat();
      return;
    }
    if (_spin.isAnimating) _spin.stop();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final color = widget.action.loading || widget.action.onPressed != null
        ? palette.textSecondary
        : palette.textTertiary;

    if (widget.action.loading) {
      return RotationTransition(
        turns: _spin,
        child: Icon(widget.action.icon, size: widget.size, color: color),
      );
    }
    return Icon(widget.action.icon, size: widget.size, color: color);
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.selectedness,
    required this.labelProgress,
    required this.labelsCapable,
    required this.pressed,
    required this.showStatusDot,
    required this.onPressedChanged,
    required this.onTap,
  });

  final NavigationItem item;
  final bool selected;
  final double selectedness;

  /// 0..1 的标签展开程度：宽度不够时连续收起，而不是整批隐藏。
  final double labelProgress;

  /// 稳定布局下的标签可容纳性；只在长按 / 悬停时用于补一个文字提示。
  final bool labelsCapable;

  /// 按住时图标轻微放大，松手回弹。
  final bool pressed;
  final bool showStatusDot;
  final ValueChanged<bool> onPressedChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    // 减少动态效果时状态点直接切换，不做缩放/淡入。
    final dotDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
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
    // 线性/实心图标交叉淡入；selectedness 由指示器位置连续驱动。
    final filled = ((selectedness - 0.3) / 0.7).clamp(0.0, 1.0);
    final iconScale = (22 + 2 * selectedness) / 24;

    final icon = SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: iconScale,
            child: Opacity(
              opacity: 1 - filled,
              child: Icon(item.icon, size: 24, color: iconColor),
            ),
          ),
          Transform.scale(
            scale: iconScale,
            child: Opacity(
              opacity: filled,
              child: Icon(item.activeIcon, size: 24, color: iconColor),
            ),
          ),
          PositionedDirectional(
            top: -2,
            end: -2,
            child: IgnorePointer(
              child: AnimatedScale(
                scale: showStatusDot ? 1 : 0,
                duration: dotDuration,
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: showStatusDot ? 1 : 0,
                  duration: dotDuration,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.accent,
                      border: Border.all(color: palette.card, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final label = labelProgress <= 0.01
        ? null
        : SizeTransition(
            sizeFactor: AlwaysStoppedAnimation<double>(labelProgress),
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: AlwaysStoppedAnimation<double>(labelProgress),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.lerp(
                      FontWeight.w500,
                      FontWeight.w600,
                      selectedness,
                    ),
                  ),
                ),
              ),
            ),
          );

    Widget content = Listener(
      // 用 Listener 而不是 InkWell 的 onHighlightChanged：后者在桌面端连
      // 鼠标悬停/焦点都会回调，会让指示器追着鼠标跑。
      onPointerDown: (_) => onPressedChanged(true),
      onPointerUp: (_) => onPressedChanged(false),
      onPointerCancel: (_) => onPressedChanged(false),
      child: InkWell(
        onTap: onTap,
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
          duration: const Duration(milliseconds: AppDimensions.navPressMs),
          curve: Curves.easeOutBack,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              if (label != null) ...[
                const SizedBox(height: 2),
                label,
              ],
            ],
          ),
        ),
      ),
    );

    if (!labelsCapable) {
      content = Tooltip(
        message: item.label,
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 500),
        child: content,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: content,
    );
  }
}
