import 'package:flutter/material.dart';
import 'package:astral_game/ui/widgets/navigation/navigation_item.dart';

class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.navigationItems,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<NavigationItem> navigationItems;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isSmallWindow = screenWidth < 300 || screenHeight < 400;

    return NavigationBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      height: isSmallWindow ? 64 : 72,
      labelBehavior: isSmallWindow
          ? NavigationDestinationLabelBehavior.alwaysHide
          : NavigationDestinationLabelBehavior.alwaysShow,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      destinations: navigationItems
          .map(
            (item) => NavigationDestination(
              icon: Icon(item.icon, size: isSmallWindow ? 20 : 24),
              selectedIcon: Icon(item.activeIcon, size: isSmallWindow ? 20 : 24),
              label: item.label,
            ),
          )
          .toList(),
    );
  }
}
