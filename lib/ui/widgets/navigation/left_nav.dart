import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:astral_game/ui/widgets/glass_capsule.dart';
import 'package:astral_game/ui/widgets/navigation/navigation_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// 宽屏侧栏：纵向悬浮玻璃胶囊导航 + 顶部品牌、底部头像。
///
/// 与底部导航共用一套动效语言：
/// * 选中指示器用弹簧动画滑动，切换时"飞"到目标项而不是原地淡入；
/// * 指示器在两 Tab 之间被纵向拉长、横向压扁，回到 Tab 时回弹成胶囊；
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
  });

  final List<NavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Uint8List? avatar;
  final String? username;
  final VoidCallback? onAvatarTap;

  @override
  State<LeftNav> createState() => _LeftNavState();
}

class _LeftNavState extends State<LeftNav>
    with SingleTickerProviderStateMixin {
  /// 单个导航项高度（与底栏胶囊高度一致）。
  static const _itemHeight = 64.0;

  /// 胶囊内上下留白。
  static const _capsulePadding = 10.0;

  static const _capsuleMargin = 12.0;

  /// 胶囊宽度：侧栏总宽去掉左右留白。
  static const _capsuleWidth = AppDimensions.sideNavWidth - _capsuleMargin * 2;

  /// 顶部品牌与底部头像各占的高度，两者相等胶囊才会正好居中。
  static const _cornerBlockHeight = 84.0;

  /// 与底栏一致的带回弹弹簧。
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 460,
    damping: 19,
  );

  /// 拖动结束时的最大初速度（项/s），避免快速甩动时弹簧冲得太远。
  static const _maxDragVelocity = 6.0;

  /// 指示器被拉长的最大比例（位于两项正中间时）。
  static const _maxStretch = 0.30;

  /// 拉长时横向被压扁的最大比例，体积守恒，像一滴液体。
  static const _maxSquash = 0.14;

  late final AnimationController _position;

  late int _currentIndex;

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
  }

  @override
  void didUpdateWidget(covariant LeftNav oldWidget) {
    super.didUpdateWidget(oldWidget);
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
  void _beginDrag(double dy, int count) {
    _position.stop();
    if (count < 2) return;
    _dragTo(dy, count);
    if (_dragging) return;
    setState(() => _dragging = true);
  }

  void _updateDrag(double dy, int count) {
    if (count < 2) return;
    _dragTo(dy, count);
  }

  /// 指示器中心跟到手指下方。
  void _dragTo(double dy, int count) {
    final raw = (dy - _capsulePadding) / _itemHeight - 0.5;
    _position.value = raw.clamp(0.0, (count - 1).toDouble());
  }

  /// 松手：吸附到最近的一项，并把拖动速度交给弹簧。
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
      // 按下就先把指示器弹向该项，不等手指抬起才动。
      _springTo(index);
      return;
    }
    // 松手后如果并没有切换选中（手势取消），再弹回当前项。
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
    final count = widget.items.length;

    return SizedBox(
      width: AppDimensions.sideNavWidth,
      child: Column(
        children: [
          // 品牌与头像各自占同一高度并水平居中，胶囊正好落在两者正中，
          // 三者共用一条中心线（侧栏 92 的一半）。
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
                                _beginDrag(details.localPosition.dy, count),
                            onVerticalDragUpdate: (details) =>
                                _updateDrag(details.localPosition.dy, count),
                            onVerticalDragEnd: (details) => _endDrag(
                              details.velocity.pixelsPerSecond.dy / _itemHeight,
                              count,
                            ),
                            onVerticalDragCancel: () => _endDrag(0, count),
                            child: AnimatedBuilder(
                              animation: _position,
                              builder: (context, _) {
                                final position = _position.value.clamp(
                                  0.0,
                                  (count - 1).toDouble(),
                                );
                                // 离最近的项越远，液滴拉得越长；回到项上复原。
                                final gap = (position - position.round()).abs();
                                final liquid = (gap / 0.5).clamp(0.0, 1.0);
                                final active =
                                    _dragging || _pressedIndex != null;
                                final press = active ? 1.08 : 1.0;

                                const baseWidth = _capsuleWidth - 16;
                                const baseHeight = _itemHeight - 10;
                                final blobWidth = baseWidth *
                                    (1 - _maxSquash * liquid);
                                final blobHeight = baseHeight *
                                    (1 + _maxStretch * liquid);
                                final center =
                                    _capsulePadding +
                                    position * _itemHeight +
                                    _itemHeight / 2;

                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // 选中指示器：位置由弹簧动画驱动，高度随距离拉伸。
                                    Positioned(
                                      left: (_capsuleWidth - blobWidth) / 2,
                                      top: center - blobHeight / 2,
                                      width: blobWidth,
                                      height: blobHeight,
                                      child: AnimatedScale(
                                        scale: press,
                                        duration: const Duration(
                                          milliseconds: 240,
                                        ),
                                        curve: Curves.easeOutBack,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: palette.accentMuted,
                                            borderRadius:
                                                BorderRadius.circular(
                                                  blobWidth,
                                                ),
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
                                                    i == _currentIndex,
                                                selectedness:
                                                    (1 - (position - i).abs())
                                                        .clamp(0.0, 1.0),
                                                pressed: _pressedIndex == i,
                                                onPressedChanged: (pressed) =>
                                                    _setPressed(i, pressed),
                                                onTap: () =>
                                                    widget.onSelected(i),
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
    );
  }
}

/// 纵向导航项：图标在上、文字在下；配色与尺寸由指示器位置连续驱动。
class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.item,
    required this.selected,
    required this.selectedness,
    required this.pressed,
    required this.onPressedChanged,
    required this.onTap,
  });

  final NavigationItem item;

  /// 语义上的当前页，只用于无障碍。
  final bool selected;

  /// 指示器与这一项的重合度：1 表示完全选中，0 表示完全未选中。
  final double selectedness;

  /// 按住时图标轻微放大，松手回弹。
  final bool pressed;
  final ValueChanged<bool> onPressedChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      // 用 Listener 而不是 InkWell 的 onHighlightChanged：后者在桌面端连
      // 鼠标悬停/焦点都会回调，会误触发按压反馈。
      child: Listener(
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
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 22 + 2 * selectedness,
                  color: Color.lerp(
                    palette.textTertiary,
                    palette.accent,
                    selectedness,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Color.lerp(
                      palette.textSecondary,
                      palette.accent,
                      selectedness,
                    ),
                    fontWeight: FontWeight.lerp(
                      FontWeight.w500,
                      FontWeight.w600,
                      selectedness,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
