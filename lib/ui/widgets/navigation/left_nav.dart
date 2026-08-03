import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/navigation/navigation_item.dart';
import 'package:flutter/material.dart';

/// 宽屏侧栏：Material [NavigationRail]。
class LeftNav extends StatelessWidget {
  const LeftNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<NavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final index = selectedIndex.clamp(0, items.length - 1);

    return ColoredBox(
      color: palette.canvas,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: _BrandBadge(),
          ),
          Expanded(
            child: NavigationRail(
              selectedIndex: index,
              onDestinationSelected: onSelected,
              backgroundColor: palette.canvas,
              indicatorColor: palette.accent.withValues(alpha: 0.14),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.activeIcon),
                    label: Text(item.label),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.astralPalette.shadowSoft,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/logo.png', fit: BoxFit.cover),
    );
  }
}
