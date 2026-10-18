import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// 一级 Tab 页面统一页头：可选状态副标题 + 可选右侧操作。
///
/// 当前页面已由底部导航指示，因此不再显示页面标题。
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    this.subtitle,
    this.actions = const [],
    this.horizontalPadding = AppDimensions.pagePaddingH,
  });

  final String? subtitle;
  final List<Widget> actions;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final subtitleText = subtitle;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 8),
      child: Row(
        children: [
          if (subtitleText != null && subtitleText.isNotEmpty)
            Expanded(
              child: Text(
                subtitleText,
                style: textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}
