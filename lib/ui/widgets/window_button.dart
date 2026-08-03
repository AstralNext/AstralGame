import 'package:flutter/material.dart';

class WindowButton extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final Color hoverColor;
  final Color iconColor;
  final VoidCallback onTap;

  const WindowButton({
    super.key,
    required this.icon,
    required this.iconSize,
    required this.hoverColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: SizedBox(
          width: 46,
          height: 32,
          child: Icon(
            icon,
            size: iconSize,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}
