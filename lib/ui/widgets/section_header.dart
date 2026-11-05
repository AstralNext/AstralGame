import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// 分区标题的语气，决定字号权重、颜色与是否使用计数徽章。
enum SectionHeaderTone {
  /// 设置页卡片上方的说明性小标题。
  muted,

  /// 收藏页“置顶 / 全部收藏”等分组标题。
  strong,

  /// 联机页成员分区标题。
  accent,
}

/// 全站统一的分区标题：标题 + 可选副标题 + 可选计数 + 可选尾部操作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    this.tone = SectionHeaderTone.strong,
    this.trailing,
    this.padding,
  });

  final String title;
  final int? count;
  final String? subtitle;
  final SectionHeaderTone tone;

  /// 右侧操作（例如成员列表的“简洁/详细”开关）。
  final Widget? trailing;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    final isMuted = tone == SectionHeaderTone.muted;
    final isAccent = tone == SectionHeaderTone.accent;

    final titleStyle = textTheme.titleSmall?.copyWith(
      fontWeight: isMuted
          ? FontWeight.w600
          : (isAccent ? FontWeight.w700 : FontWeight.w800),
      letterSpacing: 0.2,
      color: isMuted
          ? palette.textSecondary
          : (isAccent ? palette.accent : palette.textPrimary),
    );

    final effectivePadding =
        padding ??
        switch (tone) {
          SectionHeaderTone.muted => const EdgeInsets.fromLTRB(
            AppDimensions.space4,
            0,
            AppDimensions.space4,
            AppDimensions.space8,
          ),
          SectionHeaderTone.strong => const EdgeInsets.fromLTRB(
            AppDimensions.space2,
            AppDimensions.space4,
            AppDimensions.space2,
            0,
          ),
          SectionHeaderTone.accent => const EdgeInsets.only(
            left: AppDimensions.space4,
          ),
        };

    return Padding(
      padding: effectivePadding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: AppDimensions.space8),
                      if (tone == SectionHeaderTone.strong)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.space8,
                            vertical: AppDimensions.space2,
                          ),
                          decoration: BoxDecoration(
                            color: palette.accentMuted,
                            borderRadius: BorderRadius.circular(
                              AppDimensions.radiusPill,
                            ),
                          ),
                          child: Text(
                            '$count',
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: palette.accent,
                            ),
                          ),
                        )
                      else
                        Text(
                          '$count',
                          style: textTheme.labelSmall?.copyWith(
                            color: palette.textTertiary,
                          ),
                        ),
                    ],
                  ],
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppDimensions.space8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
