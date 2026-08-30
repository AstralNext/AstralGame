import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/astral_grouped_tile.dart';
import 'package:flutter/material.dart';

class AstralSettingItem {
  const AstralSettingItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.subtitleMuted = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool subtitleMuted;
  final VoidCallback onTap;
}

/// 设置页分区：小标题与分组卡片。
class AstralSettingsSection extends StatelessWidget {
  const AstralSettingsSection({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<AstralSettingItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        AstralCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                AstralGroupedTile(
                  icon: items[i].icon,
                  label: items[i].label,
                  subtitle: items[i].subtitle,
                  subtitleMuted: items[i].subtitleMuted,
                  onTap: items[i].onTap,
                  index: i,
                  count: items.length,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 设置子页内多行开关/表单的卡片容器。
class AstralSettingsFormCard extends StatelessWidget {
  const AstralSettingsFormCard({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.leading,
  });

  final List<Widget> children;
  final String? title;
  final String? subtitle;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AstralCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  if (leading != null) ...[
                    Icon(leading, color: scheme.primary, size: AppDimensions.iconSize),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (title != null) const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}
