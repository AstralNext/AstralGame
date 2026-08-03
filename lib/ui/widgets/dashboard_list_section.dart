import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:flutter/material.dart';

/// 仪表盘列表分区：标题与可选 [AstralCard] 分组。
class DashboardListSection extends StatelessWidget {
  const DashboardListSection({
    super.key,
    required this.title,
    this.count,
    this.subtitle,
    required this.child,
    this.useCard = true,
  });

  final String title;
  final int? count;
  final String? subtitle;
  final Widget child;
  final bool useCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final palette = context.astralPalette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Text(
                title,
                style: theme.labelLarge?.copyWith(
                  color: palette.accent,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$count',
                  style: theme.labelSmall?.copyWith(
                    color: palette.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              subtitle!,
              style: theme.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (useCard)
          AstralCard(padding: EdgeInsets.zero, child: child)
        else
          child,
      ],
    );
  }
}

/// 无背景的空状态（避免突兀的色块容器）。
class DashboardListEmptyHint extends StatelessWidget {
  const DashboardListEmptyHint({
    super.key,
    required this.icon,
    required this.message,
    this.detail,
  });

  final IconData icon;
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 40, color: palette.textTertiary),
          const SizedBox(height: 12),
          Text(
            message,
            style: theme.bodyMedium?.copyWith(color: palette.textSecondary),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: theme.bodySmall?.copyWith(color: palette.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
