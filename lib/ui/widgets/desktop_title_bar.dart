import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/window_button.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面窗口标题栏（拖拽 + 三窗口按钮）。
///
/// 由父级 Shell 维护 [isMaximized] 状态，通过 WindowListener 同步
/// 最大化/还原事件，避免本地状态与系统真实状态漂移（双击标题栏、
/// 系统菜单最大化、拖拽到顶部边缘都不会触发按钮自身 setState）。
///
/// [center] 非空时隐藏应用名，中间区域显示该组件（如收藏页搜索胶囊）。
class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({
    super.key,
    required this.onClose,
    required this.isMaximized,
    required this.onToggleMaximize,
    this.center,
  });

  final VoidCallback onClose;
  final bool isMaximized;
  final Future<void> Function() onToggleMaximize;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: SizedBox(
        height: 44,
        child: Container(
          color: palette.canvas,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const SizedBox(width: 8),
              if (center == null)
                Expanded(
                  child: Text(
                    'Astral Game',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: center,
                    ),
                  ),
                ),
              WindowButton(
                icon: Icons.remove,
                iconSize: 16,
                hoverColor: palette.accentMuted,
                iconColor: palette.textPrimary,
                onTap: () => windowManager.minimize(),
              ),
              WindowButton(
                icon: isMaximized ? Icons.filter_none : Icons.crop_square,
                iconSize: 14,
                hoverColor: palette.accentMuted,
                iconColor: palette.textPrimary,
                onTap: () => onToggleMaximize(),
              ),
              WindowButton(
                icon: Icons.close,
                iconSize: 16,
                hoverColor: palette.error.withValues(alpha: 0.2),
                iconColor: palette.textPrimary,
                onTap: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
