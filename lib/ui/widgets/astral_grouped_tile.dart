import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/grouped_tile_shape.dart';
import 'package:flutter/material.dart';

/// 分组卡片内的设置行（MD3：主色图标 + 内部分隔线，无卡片描边）。
class AstralGroupedTile extends StatelessWidget {
  const AstralGroupedTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.index,
    required this.count,
    this.subtitle,
    this.subtitleMuted = false,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool subtitleMuted;
  final VoidCallback onTap;
  final int index;
  final int count;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = context.astralPalette;
    final divider = theme.dividerColor;
    final shape = groupedTileShape(index: index, count: count);
    final borderRadius = groupedTileBorderRadius(index: index, count: count);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            splashColor: palette.accentMuted,
            highlightColor: palette.accent.withValues(alpha: 0.08),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                subtitle != null ? 12 : 14,
                12,
                subtitle != null ? 12 : 14,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: scheme.primary,
                    size: AppDimensions.iconSize,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: subtitleMuted
                                  ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider && index < count - 1)
          Divider(height: 1, thickness: 1, indent: 56, color: divider),
      ],
    );
  }
}
