import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// 窄屏成员列表加载骨架（节点尚未轮询到时）。
class DashboardMembersSkeleton extends StatefulWidget {
  const DashboardMembersSkeleton({
    super.key,
    this.rows = 3,
  });

  final int rows;

  @override
  State<DashboardMembersSkeleton> createState() =>
      _DashboardMembersSkeletonState();
}

class _DashboardMembersSkeletonState extends State<DashboardMembersSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final base = palette.textTertiary.withValues(alpha: 0.22);
    final highlight = palette.textTertiary.withValues(alpha: 0.42);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final color = Color.lerp(base, highlight, t)!;
        return Column(
          children: [
            for (var i = 0; i < widget.rows; i++) ...[
              if (i > 0) Divider(height: 1, color: palette.divider.withValues(alpha: 0.25)),
              _SkeletonRow(color: color),
            ],
          ],
        );
      },
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(color, widthFactor: 0.42, height: 12),
                const SizedBox(height: 8),
                _bar(color, widthFactor: 0.68, height: 10),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(Color color, {required double widthFactor, required double height}) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
