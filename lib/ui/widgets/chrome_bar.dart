import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// 顶栏公共骨架：应用名 / 中间插槽 + 右侧操作。
///
/// 手机模拟顶栏与桌面窗口标题栏共用，避免两套高度、内边距与标题样式漂移。
class ChromeBar extends StatelessWidget {
  const ChromeBar({
    super.key,
    required this.trailing,
    this.center,
    this.minHeight = 48,
    this.background,
    this.applySafeArea = false,
  });

  /// 右侧内容（头像胶囊 / 窗口按钮组）。
  final Widget trailing;

  /// 非空时隐藏应用名，中间区域显示该组件（如搜索胶囊）。
  final Widget? center;

  final double minHeight;
  final Color? background;

  /// 是否让出顶部系统安全区（手机端）。
  final bool applySafeArea;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    Widget bar = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.space12),
        child: Row(
          children: [
            const SizedBox(width: AppDimensions.space8),
            Expanded(
              child: center == null
                  ? Text(
                      'Astral Game',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: center,
                      ),
                    ),
            ),
            trailing,
          ],
        ),
      ),
    );

    if (applySafeArea) {
      bar = SafeArea(bottom: false, child: bar);
    }
    if (background != null) {
      bar = Material(color: background, child: bar);
    }
    return bar;
  }
}
