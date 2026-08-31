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

/// 分区标题：卡片上方的小号灰字（MD3 section header），可带一行副标题。
/// [AstralSettingsSection] 与 [AstralSettingsFormCard] 共用，保证两种容器标题一致。
Widget buildSettingsHeader(
  BuildContext context,
  String text, {
  String? subtitle,
}) {
  final theme = Theme.of(context);
  final style = theme.textTheme.titleSmall?.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
  return Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: style),
        if (subtitle != null)
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

/// 延迟构建行：FormCard 构建时注入 index/count，自动处理分隔线与首尾圆角。
/// 通常返回 [AstralGroupedTile]（需要响应 signal 时可包一层 `Watch`）。
typedef AstralSettingRow = Widget Function(int index, int count);

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildSettingsHeader(context, title),
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
///
/// [rows] 用 builder 延迟构建，[AstralGroupedTile] 自动获得 index/count，
/// 条件增减行时无需手写下标。
class AstralSettingsFormCard extends StatelessWidget {
  const AstralSettingsFormCard({
    super.key,
    required this.rows,
    this.title,
    this.subtitle,
  });

  final List<AstralSettingRow> rows;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          buildSettingsHeader(context, title!, subtitle: subtitle),
        AstralCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) rows[i](i, rows.length),
            ],
          ),
        ),
      ],
    );
  }
}
