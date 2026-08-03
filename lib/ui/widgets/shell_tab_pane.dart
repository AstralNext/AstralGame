import 'package:astral_game/config/app_dimensions.dart';
import 'package:flutter/material.dart';

/// 保留 [IndexedStack] 式多 Tab 状态，仅在 Tab 被选中时播放淡入 + 轻微上移动画。
class ShellTabStack extends StatelessWidget {
  const ShellTabStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          ShellTabPane(
            key: ValueKey('shell_tab_$i'),
            active: i == index,
            child: children[i],
          ),
      ],
    );
  }
}

class ShellTabPane extends StatefulWidget {
  const ShellTabPane({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<ShellTabPane> createState() => _ShellTabPaneState();
}

class _ShellTabPaneState extends State<ShellTabPane>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: AppDimensions.fadeDurationMs);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fade = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(curved);
    if (widget.active) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(ShellTabPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.forward(from: 0);
    } else if (!widget.active && oldWidget.active) {
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
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: IgnorePointer(
          ignoring: !widget.active,
          child: TickerMode(
            enabled: widget.active,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
