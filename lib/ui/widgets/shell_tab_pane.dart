import 'package:astral_game/config/app_dimensions.dart';
import 'package:flutter/material.dart';

/// 保留 [IndexedStack] 式多 Tab 状态，仅在 Tab 被选中时播放进场动画。
///
/// [IndexedStack] 本身也是 Stack：只绘制当前页、其余页用 Offstage 兜住，
/// 但只能瞬间切换、没法做淡入淡出，所以这里自己管 Stack：
/// - 只构建访问过的页面，冷启动不会一次性 build 四个页面；
/// - 当前页永远放在最后绘制，切换/回切时不会被旧页压在下面；
/// - 未激活的页面用 [IgnorePointer] + [ExcludeSemantics] 屏蔽，不可点、不被读屏。
///
/// 过渡是串行的：旧页先淡出，新页再淡入并轻微上移。
/// 两个不同页面同时半透明地叠在一起会互相穿透、透出背景，
/// 看起来“糊”且没有方向感，这也是之前切换观感奇怪的原因。
class ShellTabStack extends StatefulWidget {
  const ShellTabStack({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<ShellTabStack> createState() => _ShellTabStackState();
}

class _ShellTabStackState extends State<ShellTabStack> {
  /// 访问过的 Tab：页面一旦构建就保留状态，没去过的 Tab 不占用构建开销。
  late final List<bool> _visited;

  @override
  void initState() {
    super.initState();
    _visited = [
      for (var i = 0; i < widget.children.length; i++) i == widget.index,
    ];
  }

  @override
  void didUpdateWidget(ShellTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited[widget.index] = true;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 先画非当前页，当前页最后画，保证它在最上层。
        for (var i = 0; i < widget.children.length; i++)
          if (i != widget.index && _visited[i]) _buildPane(i),
        _buildPane(widget.index),
      ],
    );
  }

  Widget _buildPane(int i) {
    return ShellTabPane(
      key: ValueKey('shell_tab_$i'),
      active: i == widget.index,
      child: widget.children[i],
    );
  }
}

class ShellTabPane extends StatefulWidget {
  const ShellTabPane({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<ShellTabPane> createState() => _ShellTabPaneState();
}

class _ShellTabPaneState extends State<ShellTabPane>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: AppDimensions.fadeDurationMs);

  /// 旧页退场所占的时间比例（约 90ms）：留出这一段，新页才开始进场。
  static const _exitFraction = 0.36;

  /// 新页进场时自下方上移的距离（占页面高度的比例）。
  static const _rise = 0.02;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.active ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(ShellTabPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      // 正常切换从 0 开始，前 [_exitFraction] 段保持全透明，等旧页退完再进场。
      // 快速来回切时从中断处继续，避免每次都先空出一段背景。
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // 页面只构建一次：动画每帧只改透明度和位移，切换时不会重建内容。
      child: IgnorePointer(
        ignoring: !widget.active,
        child: ExcludeSemantics(
          excluding: !widget.active,
          child: TickerMode(enabled: widget.active, child: widget.child),
        ),
      ),
      builder: (context, child) {
        final progress = _controller.value;
        // 进场：等待旧页退场后淡入并回落到原位。
        final enter = const Interval(
          _exitFraction,
          1,
          curve: Curves.easeOutCubic,
        ).transform(progress);
        // 退场：只用前 [_exitFraction] 的时间淡出，随后保持透明、不再绘制。
        final exit = const Interval(
          1 - _exitFraction,
          1,
          curve: Curves.easeOutCubic,
        ).transform(progress);
        final opacity = widget.active ? enter : exit;
        final rise = widget.active ? _rise * (1 - enter) : 0.0;
        return Opacity(
          opacity: opacity,
          child: FractionalTranslation(
            translation: Offset(0, rise),
            child: child,
          ),
        );
      },
    );
  }
}
