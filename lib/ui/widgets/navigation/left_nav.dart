import 'dart:typed_data';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:astral_game/ui/widgets/navigation/navigation_item.dart';
import 'package:flutter/material.dart';

/// 宽屏侧栏：导航 + 底部头像。
class LeftNav extends StatelessWidget {
  const LeftNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.avatar,
    this.username,
    this.onAvatarTap,
  });

  final List<NavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Uint8List? avatar;
  final String? username;
  final VoidCallback? onAvatarTap;

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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Tooltip(
              message: username?.isNotEmpty == true ? username! : '编辑资料',
              child: InkWell(
                onTap: onAvatarTap,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AvatarWidget(avatar: avatar, onTap: onAvatarTap),
                ),
              ),
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
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
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
