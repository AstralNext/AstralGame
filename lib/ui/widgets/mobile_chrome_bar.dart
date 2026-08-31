import 'dart:typed_data';

import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:flutter/material.dart';

/// 桌面端不支持时的手机/平板顶栏：模拟桌面标题栏，头像落在窗口按钮区域。
///
/// [center] 非空时隐藏应用名，中间区域显示该组件（如收藏页搜索胶囊）。
class MobileChromeBar extends StatelessWidget {
  const MobileChromeBar({
    super.key,
    required this.avatar,
    required this.onAvatarTap,
    this.center,
  });

  final Uint8List? avatar;
  final VoidCallback onAvatarTap;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    return Material(
      color: palette.canvas,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Padding(
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
                AvatarWidget(avatar: avatar, size: 36, onTap: onAvatarTap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
