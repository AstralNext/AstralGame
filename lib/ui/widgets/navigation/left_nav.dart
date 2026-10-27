import 'dart:typed_data';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:astral_game/ui/widgets/glass_capsule.dart';
import 'package:astral_game/ui/widgets/navigation/liquid_nav.dart';
import 'package:astral_game/ui/widgets/navigation/navigation_item.dart';
import 'package:flutter/material.dart';

/// 宽屏侧栏：纵向悬浮玻璃胶囊导航 + 顶部品牌、底部头像。
///
/// 与底部导航共用同一套 [LiquidNavController] 物理：
/// * 选中指示器用弹簧动画滑动，切换时“飞”到目标项而不是原地淡入；
/// * 指示器在两项之间被纵向拉长、横向压扁，并按速度做非对称拖尾；
/// * 按住后上下拖动时指示器跟手，松手吸附到最近的一项；
/// * 按住时指示器与图标轻微放大，松手弹簧回弹。
class LeftNav extends StatefulWidget {
  const LeftNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.avatar,
    this.username,
    this.onAvatarTap,
    this.statusDots = const <int>{},
  });

  final List<NavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Uint8List? avatar;
  final String? username;
  final VoidCallback? onAvatarTap;

  /// 需要显示状态点的导航项索引（例如联机中）。
  final Set<int> statusDots;

  @override
  State<LeftNav> createState() => _LeftNavState();
}

class _LeftNavState extends State<LeftNav> with TickerProviderStateMixin {
  /// 单个导航项高度（与底栏胶囊高度一致）。
  static const _itemHeight = 64.0;

  /// 胶囊内上下留白。
  static const _capsulePadding = 10.0;

  /// 胶囊左右留白：只给投影留一点空间，胶囊保持原宽度。
  ///
  /// 侧栏与主体之间的间隙由页面左侧内边距收紧
  /// （[AppDimensions.pagePaddingHWithSideNav]），不要把胶囊撑宽。
  static const _capsuleInset = 12.0;

  /// 胶囊宽度：侧栏总宽去掉两侧的投影留白。
  static const _capsuleWidth = AppDimensions.sideNavWidth - _capsuleInset * 2;

  /// 顶部品牌与底部头像各占的高度，两者相等胶囊才会正好居中。
  static const _cornerBlockHeight = 84.0;

  /// 指示器被拉长的最大比例（位于两项正中间时）。
  static const _maxStretch = 0.30;

  /// 拉长时横向被压扁的最大比例，体积守恒，像一滴液体。
  static const _maxSquash = 0.14;

  late final LiquidNavController _liquid;

  @override
  void initState() {
    super.initState();
    _liquid = LiquidNavController(
      vsync: this,
      count: widget.items.length,
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
  void didUpdateWidget(covariant LeftNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    _liquid.updateSelection(widget.selectedIndex);
  }

  @override
  void dispose() {
    _liquid.dispose();
    super.dispose();
  }

  double _dragPosition(double dy) =>
      (dy - _capsulePadding) / _itemHeight - 0.5;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final count = widget.items.length;
    final textScale = MediaQuery.textScalerOf(context).scale(11) / 11;
    final labelsCapable = textScale < 1.7;
    final labelProgress = ((1.9 - textScale) / 0.4).clamp(0.0, 1.0);

    return SizedBox(
      width: AppDimensions.sideNavWidth,
      // 胶囊左右留白对称，品牌、胶囊、头像共用同一条中心线。
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _capsuleInset),
        child: Column(
          children: [
            // 品牌与头像各自占同一高度并水平居中，胶囊正好落在两者正中，
            // 三者共用一条中心线。
            const SizedBox(
              height: _cornerBlockHeight,
              child: Center(child: _BrandBadge()),
            ),
            Expanded(
              child: Center(
                // 窗口被压得很矮时宁可裁掉，也不要让胶囊撑破布局。
                // 这里只用它提供无界高度，滚动本身是关掉的。
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  // 侧栏留白比投影半径小，交给 ScrollView 裁会把投影裁成方块。
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: GlassCapsule(
                    radius: BorderRadius.circular(32),
                    child: SizedBox(
                      width: _capsuleWidth,
                      height: count * _itemHeight + _capsulePadding * 2,
                      child: count == 0
                          ? const SizedBox.shrink()
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              // 按住后上下拖动：指示器跟手，松手吸附到最近的一项。
                              onVerticalDragStart: (details) =>
                                  _liquid.beginDrag(
                                    _dragPosition(details.localPosition.dy),
                                  ),
                              onVerticalDragUpdate: (details) =>
                                  _liquid.updateDrag(
                                    _dragPosition(details.localPosition.dy),
                                  ),
                              onVerticalDragEnd: (details) => _liquid.endDrag(
                                details.velocity.pixelsPerSecond.dy / _itemHeight,
                              ),
                              onVerticalDragCancel: () => _liquid.endDrag(0),
                              child: AnimatedBuilder(
                                animation: _liquid.listenable,
                                builder: (context, _) {
                                  final position = _liquid.renderPosition;
                                  final liquid = _liquid.liquidAmount;
                                  final speed = _liquid.velocityRatio;
                                  final direction =
                                      _liquid.position.velocity.sign;
                                  final stretch =
                                      _maxStretch *
                                          liquid *
                                          (_liquid.dragging ? 1.0 : 0.78) +
                                      0.18 * speed;
                                  final squash =
                                      _maxSquash * liquid + 0.10 * speed;
                                  const baseWidth = _capsuleWidth - 16;
                                  const baseHeight = _itemHeight - 10;
                                  final center =
                                      _capsulePadding +
                                      position * _itemHeight +
                                      _itemHeight / 2 -
                                      direction * _itemHeight * 0.02 * speed;

                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      // 指示器只走绘制：位置、拉伸、按压都不触发布局。
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: CustomPaint(
                                            painter: LiquidNavPainter(
                                              axis: Axis.vertical,
                                              center: center,
                                              crossExtent: baseWidth,
                                              baseLength: baseHeight,
                                              lengthFactor: 1 + stretch,
                                              crossFactor: 1 - squash,
                                              lift: _liquid.liftAmount,
                                              palette: palette,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: _capsulePadding,
                                        ),
                                        child: Column(
                                          children: [
                                            for (var i = 0; i < count; i++)
                                              SizedBox(
                                                height: _itemHeight,
                                                width: _capsuleWidth,
                                                child: _SideNavItem(
                                                  item: widget.items[i],
                                                  selected:
                                                      i == widget.selectedIndex,
                                                  selectedness:
                                                      (1 -
                                                              (position - i)
                                                                  .abs())
                                                          .clamp(0.0, 1.0),
                                                  labelProgress: labelProgress,
                                                  labelsCapable: labelsCapable,
                                                  pressed:
                                                      _liquid.pressedIndex ==
                                                          i &&
                                                      !_liquid.reduceMotion,
                                                  showStatusDot: widget
                                                      .statusDots
                                                      .contains(i),
                                                  onPressedChanged: (pressed) =>
                                                      _liquid.setPressed(
                                                        i,
                                                        pressed,
                                                      ),
                                                  onTap: () => _liquid.tap(i),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: _cornerBlockHeight,
              child: Center(
                child: Tooltip(
                  message: widget.username?.isNotEmpty == true
                      ? widget.username!
                      : '编辑资料',
                  child: InkWell(
                    onTap: widget.onAvatarTap,
                    borderRadius: BorderRadius.circular(28),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: AvatarWidget(
                        avatar: widget.avatar,
                        onTap: widget.onAvatarTap,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 纵向导航项：图标在上、文字在下；配色与尺寸由指示器位置连续驱动。
class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
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

  /// 语义上的当前页，只用于无障碍。
  final bool selected;

  /// 指示器与这一项的重合度：1 表示完全选中，0 表示完全未选中。
  final double selectedness;

  /// 0..1 的标签展开程度；系统字号过大时连续收起，避免撑破 64 高。
  final double labelProgress;

  /// 稳定布局下是否还能容纳文字；不能时用 Tooltip 兜底。
  final bool labelsCapable;
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
      // 鼠标悬停/焦点都会回调，会误触发按压反馈。
      onPointerDown: (_) => onPressedChanged(true),
      onPointerUp: (_) => onPressedChanged(false),
      onPointerCancel: (_) => onPressedChanged(false),
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(28),
        // 玻璃上只用极轻的主题色高亮，避免焦点色留在玻璃里。
        focusColor: palette.accent.withValues(alpha: 0.06),
        hoverColor: palette.accent.withValues(alpha: 0.04),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedScale(
          scale: pressed ? 1.08 : 1.0,
          duration: const Duration(milliseconds: AppDimensions.navPressMs),
          curve: Curves.easeOutBack,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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

class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        boxShadow: [
          BoxShadow(
            color: context.astralPalette.shadowSoft,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/logo.png', fit: BoxFit.cover),
    );
  }
}
