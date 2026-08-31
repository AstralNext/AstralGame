import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// 空状态操作按钮样式。
enum EmptyActionStyle { text, tonal, filled }

/// 通用空状态：图标 + 标题 +（可选）副标题 +（可选）操作按钮。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionStyle = EmptyActionStyle.tonal,
    this.actionIcon,
    this.iconSize = 64,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EmptyActionStyle actionStyle;
  final IconData? actionIcon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: palette.textTertiary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              switch (actionStyle) {
                EmptyActionStyle.text => TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
                EmptyActionStyle.tonal => FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
                EmptyActionStyle.filled => FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon ?? Icons.add),
                  label: Text(actionLabel!),
                ),
              },
            ],
          ],
        ),
      ),
    );
  }
}
